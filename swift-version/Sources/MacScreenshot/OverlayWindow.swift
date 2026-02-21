import Cocoa

class OverlayWindow: NSWindow {
    /// backgroundImage: 已截取的全屏 CGImage，作为选区背景
    init(screen: NSScreen, backgroundImage: CGImage, onCrop: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
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
            backgroundImage: backgroundImage,
            onCrop: onCrop,
            onCancel: onCancel
        )
        self.contentView = overlay
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
