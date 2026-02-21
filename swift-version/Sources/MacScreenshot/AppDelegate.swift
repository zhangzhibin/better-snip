import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayWindow: OverlayWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Screenshot") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "S"
            }
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Capture Full Screen", action: #selector(captureFullScreen), keyEquivalent: "f"))
        menu.addItem(NSMenuItem(title: "Capture Region", action: #selector(captureRegion), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func captureFullScreen() {
        if ScreenCapture.captureFullScreen() {
            FlashWindow.show()
        }
    }

    @objc private func captureRegion() {
        overlayWindow = OverlayWindow { [weak self] rect in
            self?.overlayWindow?.close()
            self?.overlayWindow = nil
            // 等窗口完全消失后再截屏，避免选区 UI 被截入
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if ScreenCapture.captureRegion(rect: rect) {
                    FlashWindow.show()
                }
            }
        } onCancel: { [weak self] in
            self?.overlayWindow?.close()
            self?.overlayWindow = nil
        }
        overlayWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
