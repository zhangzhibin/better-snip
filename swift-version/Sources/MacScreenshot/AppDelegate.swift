import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var captureItem: NSMenuItem!
    private var skipPreviewItem: NSMenuItem!
    private var pickerWindows: [ScreenPickerWindow] = []
    private var eventMonitor: Any?
    private var editorWindow: AnnotationEditorWindow?
    private var preferencesWindow: PreferencesWindow?
    private var aboutWindow: AboutWindow?
    private var captureSession: CaptureSession?
    private var preferencesShown = false
    private var shortcutSuspended = false
    private var lastCaptureUptime: TimeInterval = 0

    func setupTray() {
        HotKeyCenter.shared.onPressed = { [weak self] in
            self?.toggleUnifiedCapture()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Simple Snip") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "📷"
            }
        }

        let menu = NSMenu()

        captureItem = NSMenuItem(title: "Capture", action: #selector(toggleUnifiedCapture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        updateCaptureMenuShortcut()

        let fullItem = NSMenuItem(title: "Capture Full Screen", action: #selector(captureFullScreen), keyEquivalent: "")
        fullItem.target = self
        menu.addItem(fullItem)

        skipPreviewItem = NSMenuItem(title: "Skip Preview", action: #selector(toggleSkipPreview), keyEquivalent: "")
        skipPreviewItem.target = self
        menu.addItem(skipPreviewItem)
        updateSkipPreviewMenu()

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About Simple Snip", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.keyEquivalentModifierMask = .command
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu

        aboutWindow = AboutWindow()
        DispatchQueue.main.async { [weak self] in
            self?.aboutWindow?.present(autoDismiss: true)
        }
    }

    // MARK: - 统一截图（拖选 / 点窗口）

    @objc private func toggleUnifiedCapture() {
        if captureSession != nil {
            captureSession?.cancel()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastCaptureUptime < 0.35 { return }
        lastCaptureUptime = now
        guard editorWindow == nil else { return }
        aboutWindow?.dismiss()
        closeAllPickers()

        let session = CaptureSession()
        session.onCapture = { [weak self] image, screen, anchor in
            self?.captureSession = nil
            self?.deliver(image: image, on: screen, anchor: anchor)
        }
        session.onRegion = { [weak self] screen, rect in
            self?.captureSession = nil
            self?.captureRegion(rect, on: screen)
        }
        session.onWindow = { [weak self] info in
            self?.captureSession = nil
            self?.captureWindow(info)
        }
        session.onCancel = { [weak self] in
            self?.captureSession = nil
            self?.updateActivationPolicy()
        }
        captureSession = session
        session.start()
    }

    private func captureRegion(_ rect: NSRect, on screen: NSScreen) {
        let anchor = ScreenCapture.appKitRect(fromFlippedLocal: rect, on: screen)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            let displayID = ScreenCapture.displayID(for: screen)
            guard let full = ScreenCapture.captureFullImage(displayID: displayID),
                  let cropped = ScreenCapture.cropImage(full, rect: rect, scale: screen.backingScaleFactor) else { return }
            self?.deliver(image: cropped, on: screen, anchor: anchor)
        }
    }

    private func captureWindow(_ info: WindowInfo) {
        let appKit = WindowPicker.quartzToAppKit(rect: info.bounds)
        let screen = NSScreen.screens.first { $0.frame.intersects(appKit) } ?? NSScreen.screens.first
        guard let screen else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let image = WindowPicker.captureWindow(windowID: info.windowID) else { return }
            self?.deliver(image: image, on: screen, anchor: appKit)
        }
    }

    // MARK: - 全屏

    @objc private func captureFullScreen() {
        guard editorWindow == nil, captureSession == nil else { return }
        aboutWindow?.dismiss()
        closeAllPickers()

        for screen in NSScreen.screens {
            let picker = ScreenPickerWindow(screen: screen, onSelect: { [weak self] selectedScreen, displayID in
                self?.handleFullScreenSelection(screen: selectedScreen, displayID: displayID)
            }, onCancel: { [weak self] in
                self?.closeAllPickers()
            })
            pickerWindows.append(picker)
            picker.orderFrontRegardless()
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.updatePickerHighlights()
            return event
        }
        updatePickerHighlights()
    }

    private func updatePickerHighlights() {
        let mouseLocation = NSEvent.mouseLocation
        for picker in pickerWindows {
            picker.pickerView?.setHighlighted(picker.targetScreen.frame.contains(mouseLocation))
        }
    }

    private func handleFullScreenSelection(screen: NSScreen, displayID: CGDirectDisplayID) {
        closeAllPickers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let fullImage = ScreenCapture.captureFullImage(displayID: displayID) else { return }
            self?.deliver(image: fullImage, on: screen, anchor: screen.visibleFrame)
        }
    }

    private func closeAllPickers() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        for window in pickerWindows {
            window.orderOut(nil)
            window.close()
        }
        pickerWindows.removeAll()
    }

    // MARK: - 标记编辑器

    /// 跳过预览时直接保存；否则打开标注窗口。
    private func deliver(image: CGImage, on screen: NSScreen, anchor: NSRect?) {
        if AppPreferences.skipPreview {
            export(image, on: screen)
        } else {
            openEditor(image: image, on: screen, anchor: anchor)
        }
    }

    private func openEditor(image: CGImage, on screen: NSScreen, anchor: NSRect?) {
        let editor = AnnotationEditorWindow(image: image, screen: screen, anchor: anchor)
        editor.onSave = { [weak self] image in
            self?.export(image, on: screen)
        }
        editor.onClose = { [weak self] in
            self?.editorWindow = nil
            self?.updateActivationPolicy()
        }
        editorWindow = editor
        updateActivationPolicy()
        editor.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 按偏好设置写入剪贴板、文件，或两者。按住 Option 时在剪贴板和文件之间对调。只存文件失败时退回剪贴板。
    private func export(_ image: CGImage, on screen: NSScreen) {
        let destination = AppPreferences.destination.resolving(optionHeld: NSEvent.modifierFlags.contains(.option))
        var ok = false
        if destination == .clipboard || destination == .both {
            ok = ScreenCapture.writeToClipboard(image)
        }
        if destination == .file || destination == .both {
            if AppPreferences.saveDirectory == nil {
                _ = chooseSaveDirectory()
            }
            let saved = AppPreferences.withSaveDirectory { ScreenCapture.saveImage(image, to: $0) } ?? nil
            if saved != nil {
                ok = true
            } else if destination == .file {
                ok = ScreenCapture.writeToClipboard(image)
            }
        }
        if ok { FlashWindow.show(on: screen) }
    }

    /// 第一次保存到文件时让用户选目录。取消则返回 nil，由调用方改存剪贴板。
    private func chooseSaveDirectory() -> URL? {
        let wasAccessory = NSApp.activationPolicy() == .accessory
        if wasAccessory {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        defer {
            if wasAccessory, editorWindow == nil, !preferencesShown {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a folder for screenshots"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        AppPreferences.rememberSaveDirectory(url)
        preferencesWindow?.refreshFolder()
        return url
    }

    // MARK: - 偏好设置

    @objc private func showAbout() {
        aboutWindow?.present(autoDismiss: false)
    }

    @objc private func showPreferences() {
        if preferencesWindow == nil {
            let window = PreferencesWindow()
            window.onSuspendShortcut = { [weak self] suspended in
                self?.setShortcutSuspended(suspended)
            }
            window.onShortcutChanged = { [weak self] in
                self?.updateCaptureMenuShortcut()
            }
            window.onSkipPreviewChanged = { [weak self] in
                self?.updateSkipPreviewMenu()
            }
            window.onClose = { [weak self] in
                self?.preferencesShown = false
                self?.updateActivationPolicy()
            }
            preferencesWindow = window
        }
        preferencesShown = true
        updateActivationPolicy()
        preferencesWindow?.center()
        preferencesWindow?.makeKeyAndOrderFront(nil)
        preferencesWindow?.refreshShortcutField()
        // 打开时不要把焦点放进快捷键栏，否则会显示成待输入而不是当前快捷键。
        preferencesWindow?.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setShortcutSuspended(_ suspended: Bool) {
        shortcutSuspended = suspended
        HotKeyCenter.shared.setSuspended(suspended)
        updateCaptureMenuShortcut()
    }

    @objc private func toggleSkipPreview() {
        AppPreferences.skipPreview.toggle()
        updateSkipPreviewMenu()
        preferencesWindow?.refreshSkipPreview()
    }

    private func updateSkipPreviewMenu() {
        skipPreviewItem?.state = AppPreferences.skipPreview ? .on : .off
    }

    private func updateCaptureMenuShortcut() {
        guard let captureItem else { return }
        if shortcutSuspended || !AppPreferences.isHotkeyEnabled {
            captureItem.keyEquivalent = ""
            captureItem.keyEquivalentModifierMask = []
            return
        }
        captureItem.keyEquivalent = AppPreferences.hotkeyCharacter.lowercased()
        captureItem.keyEquivalentModifierMask = AppPreferences.hotkeyModifiers
    }

    private func updateActivationPolicy() {
        let interactive = editorWindow != nil || preferencesShown
        NSApp.setActivationPolicy(interactive ? .regular : .accessory)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateSkipPreviewMenu()
    }
}
