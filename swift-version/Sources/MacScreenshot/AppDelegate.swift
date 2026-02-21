import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayWindows: [OverlayWindow] = []

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

        rebuildMenu()
    }

    /// 每次打开菜单前刷新屏幕列表
    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let screens = NSScreen.screens
        if screens.count > 1 {
            // 多屏幕：全屏截图用子菜单
            let fullSub = NSMenu()
            for (i, screen) in screens.enumerated() {
                let isMain = (screen == NSScreen.main)
                let w = Int(screen.frame.width)
                let h = Int(screen.frame.height)
                let title = "Screen \(i + 1)\(isMain ? " (Main)" : "") - \(w)×\(h)"
                let item = NSMenuItem(title: title, action: #selector(captureFullScreenForDisplay(_:)), keyEquivalent: "")
                item.target = self
                item.tag = Int(ScreenCapture.displayID(for: screen))
                item.representedObject = screen
                fullSub.addItem(item)
            }
            let fullItem = NSMenuItem(title: "Capture Full Screen", action: nil, keyEquivalent: "f")
            fullItem.submenu = fullSub
            menu.addItem(fullItem)
        } else {
            // 单屏幕：直接截图
            let fullItem = NSMenuItem(title: "Capture Full Screen", action: #selector(captureFullScreenMain), keyEquivalent: "f")
            fullItem.target = self
            menu.addItem(fullItem)
        }

        let regionItem = NSMenuItem(title: "Capture Region", action: #selector(captureRegion), keyEquivalent: "r")
        regionItem.target = self
        menu.addItem(regionItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - 全屏截图

    @objc private func captureFullScreenMain() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let did = ScreenCapture.displayID(for: screen)
        if ScreenCapture.captureFullScreen(displayID: did) {
            FlashWindow.show(on: screen)
        }
    }

    @objc private func captureFullScreenForDisplay(_ sender: NSMenuItem) {
        let did = CGDirectDisplayID(sender.tag)
        let screen = sender.representedObject as? NSScreen ?? NSScreen.main ?? NSScreen.screens[0]
        if ScreenCapture.captureFullScreen(displayID: did) {
            FlashWindow.show(on: screen)
        }
    }

    // MARK: - 区域截图

    @objc private func captureRegion() {
        closeAllOverlays()

        let screens = NSScreen.screens
        for screen in screens {
            let overlay = OverlayWindow(screen: screen, onCapture: { [weak self] displayID, rect in
                self?.closeAllOverlays()
                // 找到对应的 NSScreen 用于闪屏
                let targetScreen = NSScreen.screens.first { ScreenCapture.displayID(for: $0) == displayID } ?? NSScreen.main ?? NSScreen.screens[0]
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if ScreenCapture.captureRegion(displayID: displayID, rect: rect) {
                        FlashWindow.show(on: targetScreen)
                    }
                }
            }, onCancel: { [weak self] in
                self?.closeAllOverlays()
            })
            overlayWindows.append(overlay)
            overlay.makeKeyAndOrderFront(nil)
        }
    }

    private func closeAllOverlays() {
        for w in overlayWindows {
            w.close()
        }
        overlayWindows.removeAll()
    }

    // MARK: - 退出

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    /// 菜单即将打开时刷新屏幕列表
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
}
