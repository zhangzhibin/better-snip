import Cocoa

class ScreenPickerView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private let screen: NSScreen
    private let displayID: CGDirectDisplayID
    private var onSelect: (NSScreen, CGDirectDisplayID) -> Void
    private var onCancel: () -> Void
    private(set) var isHighlighted = false

    init(frame: NSRect, screen: NSScreen, displayID: CGDirectDisplayID,
         onSelect: @escaping (NSScreen, CGDirectDisplayID) -> Void,
         onCancel: @escaping () -> Void) {
        self.screen = screen
        self.displayID = displayID
        self.onSelect = onSelect
        self.onCancel = onCancel
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setHighlighted(_ value: Bool) {
        guard isHighlighted != value else { return }
        isHighlighted = value
        needsDisplay = true
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            let borderWidth: CGFloat = 4
            let inset = borderWidth / 2
            let rect = bounds.insetBy(dx: inset, dy: inset)
            NSColor.systemRed.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = borderWidth
            path.stroke()
        }
    }

    // MARK: - 鼠标事件

    override func mouseDown(with event: NSEvent) {
        onSelect(screen, displayID)
    }

    // MARK: - 键盘事件

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onCancel()
        case 36: // Enter
            onSelect(screen, displayID)
        default:
            break
        }
    }
}
