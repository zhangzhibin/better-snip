import Cocoa

class ScreenPickerWindow: NSWindow {
    let targetScreen: NSScreen
    let displayID: CGDirectDisplayID

    var pickerView: ScreenPickerView? {
        contentView as? ScreenPickerView
    }

    init(screen: NSScreen, onSelect: @escaping (NSScreen, CGDirectDisplayID) -> Void, onCancel: @escaping () -> Void) {
        self.targetScreen = screen
        self.displayID = ScreenCapture.displayID(for: screen)
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = NSColor(white: 0, alpha: 0.001)
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        self.acceptsMouseMovedEvents = true

        let pickerView = ScreenPickerView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            screen: screen,
            displayID: self.displayID,
            onSelect: onSelect,
            onCancel: onCancel
        )
        self.contentView = pickerView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func makeKey() {
        super.makeKey()
        if let view = contentView {
            makeFirstResponder(view)
        }
    }
}
