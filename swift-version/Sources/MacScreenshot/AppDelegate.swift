import Cocoa

private enum CaptureMode {
    case fullScreen
    case region
    case window
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var pickerWindows: [ScreenPickerWindow] = []
    private var overlayWindows: [OverlayWindow] = []
    private var eventMonitor: Any?
    private var currentMode: CaptureMode = .fullScreen
    /// 窗口模式下当前检测到的窗口
    private var detectedWindow: WindowInfo?
    private var editorWindow: AnnotationEditorWindow?

    func setupTray() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if #available(macOS 11.0, *),
               let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screenshot") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "📷"
            }
        }

        let menu = NSMenu()

        let fullItem = NSMenuItem(title: "Capture Full Screen", action: #selector(captureFullScreen), keyEquivalent: "f")
        fullItem.target = self
        menu.addItem(fullItem)

        let regionItem = NSMenuItem(title: "Capture Region", action: #selector(captureRegion), keyEquivalent: "r")
        regionItem.target = self
        menu.addItem(regionItem)

        let windowItem = NSMenuItem(title: "Capture Window", action: #selector(captureWindow), keyEquivalent: "w")
        windowItem.target = self
        menu.addItem(windowItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - 菜单动作

    @objc private func captureFullScreen() {
        startScreenPicker(mode: .fullScreen)
    }

    @objc private func captureRegion() {
        startScreenPicker(mode: .region)
    }

    @objc private func captureWindow() {
        startScreenPicker(mode: .window)
    }

    // MARK: - 屏幕/窗口选择

    private func startScreenPicker(mode: CaptureMode) {
        closeAllPickers()
        closeAllOverlays()
        currentMode = mode
        detectedWindow = nil

        for screen in NSScreen.screens {
            let picker = ScreenPickerWindow(screen: screen, onSelect: { [weak self] selectedScreen, displayID in
                self?.handleSelection(screen: selectedScreen, displayID: displayID)
            }, onCancel: { [weak self] in
                self?.closeAllPickers()
            })
            pickerWindows.append(picker)
            picker.orderFrontRegardless()
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMoved()
            return event
        }

        handleMouseMoved()
    }

    private func handleMouseMoved() {
        let mouseLocation = NSEvent.mouseLocation

        if currentMode == .window {
            updateWindowHighlight(mouseLocation: mouseLocation)
        } else {
            updatePickerHighlights(mouseLocation: mouseLocation)
        }
    }

    /// 全屏/区域模式：整屏红色边框
    private func updatePickerHighlights(mouseLocation: NSPoint) {
        for picker in pickerWindows {
            let isOnScreen = picker.targetScreen.frame.contains(mouseLocation)
            picker.pickerView?.setHighlighted(isOnScreen)
        }
    }

    /// 窗口模式：检测鼠标下窗口并高亮其 bounds
    private func updateWindowHighlight(mouseLocation: NSPoint) {
        let info = WindowPicker.windowUnderMouse()
        detectedWindow = info

        // 清除所有 picker 上的高亮
        for picker in pickerWindows {
            picker.pickerView?.setHighlightRect(nil)
        }

        guard let info = info else { return }

        // 将 Quartz bounds 转为 AppKit 屏幕坐标
        let appKitRect = WindowPicker.quartzToAppKit(rect: info.bounds)

        // 找到窗口所在的屏幕，在对应 picker 上绘制高亮
        for picker in pickerWindows {
            let screenFrame = picker.targetScreen.frame
            guard appKitRect.intersects(screenFrame) else { continue }

            // 转为 picker view 的本地坐标（view 坐标系 flipped，origin = 屏幕左上角）
            let localRect = NSRect(
                x: appKitRect.origin.x - screenFrame.origin.x,
                y: screenFrame.maxY - appKitRect.maxY,
                width: appKitRect.width,
                height: appKitRect.height
            )
            picker.pickerView?.setHighlightRect(localRect)
        }
    }

    private func handleSelection(screen: NSScreen, displayID: CGDirectDisplayID) {
        let mode = currentMode
        let savedWindow = detectedWindow
        closeAllPickers()

        switch mode {
        case .fullScreen:
            guard let fullImage = ScreenCapture.captureFullImage(displayID: displayID) else { return }
            openEditor(image: fullImage, on: screen)
        case .region:
            guard let fullImage = ScreenCapture.captureFullImage(displayID: displayID) else { return }
            openRegionOverlay(screen: screen, capturedImage: fullImage)
        case .window:
            guard let info = savedWindow,
                  let cgImage = WindowPicker.captureWindow(windowID: info.windowID) else { return }
            let targetScreen = NSScreen.screens.first { $0.frame.contains(WindowPicker.quartzToAppKit(rect: info.bounds).origin) } ?? screen
            openEditor(image: cgImage, on: targetScreen)
        }
    }

    private func closeAllPickers() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        for w in pickerWindows { w.close() }
        pickerWindows.removeAll()
        detectedWindow = nil
    }

    // MARK: - 区域截图

    private func openRegionOverlay(screen: NSScreen, capturedImage: CGImage) {
        closeAllOverlays()
        let scale = screen.backingScaleFactor

        let overlay = OverlayWindow(screen: screen, backgroundImage: capturedImage, onCrop: { [weak self] rect in
            self?.closeAllOverlays()
            guard let cropped = ScreenCapture.cropImage(capturedImage, rect: rect, scale: scale) else { return }
            self?.openEditor(image: cropped, on: screen)
        }, onCancel: { [weak self] in
            self?.closeAllOverlays()
        })
        overlayWindows.append(overlay)
        overlay.makeKeyAndOrderFront(nil)
    }

    private func closeAllOverlays() {
        for w in overlayWindows { w.close() }
        overlayWindows.removeAll()
    }

    // MARK: - 标记编辑器

    private func openEditor(image: CGImage, on screen: NSScreen) {
        if ScreenCapture.writeToClipboard(image) {
            FlashWindow.show(on: screen)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self = self else { return }
            NSLog("[AppDelegate] openEditor: creating editor window")
            let editor = AnnotationEditorWindow(image: image, screen: screen)
            editor.onClose = { [weak self] in
                self?.editorWindow = nil
                NSApp.setActivationPolicy(.accessory)
            }
            self.editorWindow = editor
            // agent app 需要临时切换为 regular 才能正常显示窗口
            NSApp.setActivationPolicy(.regular)
            editor.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NSLog("[AppDelegate] openEditor: window displayed")
        }
    }

    // MARK: - 退出

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
