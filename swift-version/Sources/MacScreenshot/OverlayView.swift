import Cocoa

class OverlayView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private var onCapture: (CGRect) -> Void
    private var onCancel: () -> Void
    private var startPoint: NSPoint = .zero
    private var currentPoint: NSPoint = .zero
    private var isDragging = false

    private var selectionRect: NSRect {
        NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    init(frame: NSRect, onCapture: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onCancel = onCancel
        super.init(frame: frame)
        // 使用追踪区域确保光标显示为十字
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        // 半透明蒙版
        NSColor(white: 0, alpha: 0.35).setFill()
        bounds.fill()

        if isDragging {
            let sel = selectionRect
            guard sel.width > 0, sel.height > 0 else { return }

            // 选区区域透明（挖空蒙版）
            NSColor.clear.setFill()
            sel.fill(using: .copy)

            // 白色边框
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: sel)
            border.lineWidth = 2
            border.stroke()

            // 外侧半透明阴影边框
            NSColor(white: 0, alpha: 0.5).setStroke()
            let shadow = NSBezierPath(rect: sel.insetBy(dx: -1, dy: -1))
            shadow.lineWidth = 1
            shadow.stroke()

            // 尺寸信息
            drawSizeInfo(sel)
        } else {
            // 底部提示
            drawHint()
        }
    }

    private func drawSizeInfo(_ rect: NSRect) {
        let text = String(format: "%.0f × %.0f", rect.width, rect.height)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor(white: 0, alpha: 0.65),
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = NSPoint(x: rect.minX + 8, y: rect.minY + 8)
        let bg = NSRect(origin: NSPoint(x: origin.x - 4, y: origin.y - 2), size: NSSize(width: size.width + 8, height: size.height + 4))
        NSColor(white: 0, alpha: 0.65).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    private func drawHint() {
        let text = "Drag to select · Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let x = (bounds.width - size.width) / 2
        let y = bounds.height - 40
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }

    // MARK: - 鼠标事件

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        isDragging = false
        let sel = selectionRect
        if sel.width >= 2, sel.height >= 2 {
            // 将 NSView 坐标转为屏幕坐标（isFlipped=true，左上角原点，与 CG Display 一致）
            onCapture(sel)
        } else {
            onCancel()
        }
    }

    // MARK: - 键盘事件

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            isDragging = false
            onCancel()
        case 36: // Enter
            if isDragging {
                isDragging = false
                let sel = selectionRect
                if sel.width >= 2, sel.height >= 2 {
                    onCapture(sel)
                    return
                }
            }
            onCancel()
        default:
            break
        }
    }
}
