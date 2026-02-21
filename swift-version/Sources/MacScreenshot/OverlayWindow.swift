import Cocoa

class OverlayWindow: NSWindow {
    init(onCapture: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        guard let screen = NSScreen.main else {
            super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            return
        }
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false

        let overlay = OverlayView(frame: screen.frame, onCapture: onCapture, onCancel: onCancel)
        self.contentView = overlay
    }

    // 允许窗口接收键盘事件
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
