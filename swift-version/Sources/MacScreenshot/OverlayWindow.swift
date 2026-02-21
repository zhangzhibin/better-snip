import Cocoa

class OverlayWindow: NSWindow {
    let displayID: CGDirectDisplayID

    /// onCapture 回调传出 (displayID, 选区rect)
    init(screen: NSScreen, onCapture: @escaping (CGDirectDisplayID, CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.displayID = ScreenCapture.displayID(for: screen)
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

        let overlay = OverlayView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            displayID: self.displayID,
            onCapture: onCapture,
            onCancel: onCancel
        )
        self.contentView = overlay
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
