import Cocoa

private enum CaptureMode {
    case fullScreen
    case region
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var pickerWindows: [ScreenPickerWindow] = []
    private var overlayWindows: [OverlayWindow] = []
    private var eventMonitor: Any?
    private var currentMode: CaptureMode = .fullScreen

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

    // MARK: - 屏幕选择

    private func startScreenPicker(mode: CaptureMode) {
        closeAllPickers()
        closeAllOverlays()
        currentMode = mode

        // 激活 app，确保能接收键盘事件
        NSApp.activate(ignoringOtherApps: true)

        for screen in NSScreen.screens {
            let picker = ScreenPickerWindow(screen: screen, onSelect: { [weak self] selectedScreen, displayID in
                self?.handleScreenSelected(screen: selectedScreen, displayID: displayID)
            }, onCancel: { [weak self] in
                self?.closeAllPickers()
            })
            pickerWindows.append(picker)
            picker.orderFrontRegardless()
        }

        // 全局事件监听：鼠标移动 + 键盘
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .keyDown]) { [weak self] event in
            guard let self = self, !self.pickerWindows.isEmpty else { return event }
            if event.type == .keyDown {
                return self.handlePickerKeyDown(event)
            } else {
                self.updatePickerHighlights()
            }
            return event
        }

        updatePickerHighlights()
    }

    private func handlePickerKeyDown(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 53: // Esc
            closeAllPickers()
            return nil
        case 36: // Enter — 确认当前高亮的屏幕
            if let highlighted = pickerWindows.first(where: { $0.pickerView?.isHighlighted == true }) {
                handleScreenSelected(screen: highlighted.targetScreen, displayID: highlighted.displayID)
            }
            return nil
        default:
            return event
        }
    }

    private func updatePickerHighlights() {
        let mouseLocation = NSEvent.mouseLocation
        for picker in pickerWindows {
            let isOnScreen = picker.targetScreen.frame.contains(mouseLocation)
            picker.pickerView?.setHighlighted(isOnScreen)
            if isOnScreen {
                picker.makeKey()
            }
        }
    }

    private func closeAllPickers() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        for w in pickerWindows { w.close() }
        pickerWindows.removeAll()
    }

    // MARK: - 选屏确认后立即截图

    private func handleScreenSelected(screen: NSScreen, displayID: CGDirectDisplayID) {
        let mode = currentMode
        closeAllPickers()

        // 立即截取全屏（此时选屏窗口已关闭，截到的是真实屏幕内容）
        guard let fullImage = ScreenCapture.captureFullImage(displayID: displayID) else { return }

        switch mode {
        case .fullScreen:
            if ScreenCapture.writeToClipboard(fullImage) {
                FlashWindow.show(on: screen)
            }
        case .region:
            openRegionOverlay(screen: screen, capturedImage: fullImage)
        }
    }

    // MARK: - 区域截图（在已截取的静态图上裁剪）

    private func openRegionOverlay(screen: NSScreen, capturedImage: CGImage) {
        closeAllOverlays()
        let scale = screen.backingScaleFactor

        let overlay = OverlayWindow(screen: screen, backgroundImage: capturedImage, onCrop: { [weak self] rect in
            self?.closeAllOverlays()
            if ScreenCapture.cropAndWrite(image: capturedImage, rect: rect, scale: scale) {
                FlashWindow.show(on: screen)
            }
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

    // MARK: - 退出

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
