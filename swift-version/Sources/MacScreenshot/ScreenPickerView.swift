import Cocoa

class ScreenPickerView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private let screen: NSScreen
    private let displayID: CGDirectDisplayID
    private var onSelect: (NSScreen, CGDirectDisplayID) -> Void
    private var onCancel: () -> Void
    private(set) var isHighlighted = false

    /// 窗口模式：高亮特定窗口区域（view 坐标系，flipped），非 nil 时替代全屏红色边框
    private(set) var highlightRect: NSRect?

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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setHighlighted(_ value: Bool) {
        guard isHighlighted != value else { return }
        isHighlighted = value
        highlightRect = nil
        needsDisplay = true
    }

    func setHighlightRect(_ rect: NSRect?) {
        highlightRect = rect
        needsDisplay = true
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        if let rect = highlightRect {
            // 窗口模式：蓝色边框高亮窗口区域
            // 半透明蒙版覆盖全屏
            NSColor(white: 0, alpha: 0.15).setFill()
            bounds.fill()

            // 窗口区域清除蒙版
            NSColor.clear.setFill()
            rect.intersection(bounds).fill(using: .copy)

            // 蓝色边框
            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect: rect.intersection(bounds))
            border.lineWidth = 3
            border.stroke()
        } else if isHighlighted {
            // 屏幕选择模式：红色边框
            let borderWidth: CGFloat = 4
            let inset = borderWidth / 2
            let r = bounds.insetBy(dx: inset, dy: inset)
            NSColor.systemRed.setStroke()
            let path = NSBezierPath(rect: r)
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
