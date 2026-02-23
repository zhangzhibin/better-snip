import Cocoa

enum AnnotationTool: String, CaseIterable {
    case arrow, rect, ellipse, line, freehand, text, mosaic
}

class Annotation {
    var tool: AnnotationTool
    var color: NSColor
    var lineWidth: CGFloat
    var startPoint: NSPoint = .zero
    var endPoint: NSPoint = .zero
    var points: [NSPoint] = []
    var text: String = ""
    var font: NSFont = .systemFont(ofSize: 16)
    var isBold: Bool = false
    var isItalic: Bool = false
    var mosaicImage: CGImage?
    var brushWidth: CGFloat = 20
    /// 虚线模式：空数组 = 实线
    var dashPattern: [CGFloat] = []

    init(tool: AnnotationTool, color: NSColor, lineWidth: CGFloat) {
        self.tool = tool
        self.color = color
        self.lineWidth = lineWidth
    }

    /// 标记的包围框
    var frame: NSRect {
        switch tool {
        case .arrow, .line:
            return NSRect(
                x: min(startPoint.x, endPoint.x) - lineWidth,
                y: min(startPoint.y, endPoint.y) - lineWidth,
                width: abs(endPoint.x - startPoint.x) + lineWidth * 2,
                height: abs(endPoint.y - startPoint.y) + lineWidth * 2
            )
        case .rect, .ellipse:
            return normalizedRect
        case .freehand:
            guard !points.isEmpty else { return .zero }
            var minX = CGFloat.infinity, minY = CGFloat.infinity
            var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
            for p in points {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
            return NSRect(x: minX - lineWidth, y: minY - lineWidth,
                          width: maxX - minX + lineWidth * 2, height: maxY - minY + lineWidth * 2)
        case .mosaic:
            guard !points.isEmpty else { return .zero }
            var minX = CGFloat.infinity, minY = CGFloat.infinity
            var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
            for p in points {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
            let hw = brushWidth / 2
            return NSRect(x: minX - hw, y: minY - hw,
                          width: maxX - minX + brushWidth, height: maxY - minY + brushWidth)
        case .text:
            let size = textSize
            return NSRect(origin: startPoint, size: size)
        }
    }

    /// rect/ellipse 的规范化矩形
    var normalizedRect: NSRect {
        NSRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
    }

    var textSize: NSSize {
        let attrs = textAttributes
        return (text as NSString).size(withAttributes: attrs)
    }

    var textAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color]
    }

    // MARK: - 绘制

    func draw() {
        color.setStroke()
        color.setFill()

        switch tool {
        case .arrow:
            drawArrow()
        case .rect:
            let path = NSBezierPath(rect: normalizedRect)
            path.lineWidth = lineWidth
            applyDash(to: path, isShape: true)
            path.stroke()
        case .ellipse:
            let path = NSBezierPath(ovalIn: normalizedRect)
            path.lineWidth = lineWidth
            applyDash(to: path, isShape: true)
            path.stroke()
        case .line:
            let path = NSBezierPath()
            path.move(to: startPoint)
            path.line(to: endPoint)
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            applyDash(to: path, isShape: false)
            path.stroke()
        case .freehand:
            guard points.count >= 2 else { return }
            let path = NSBezierPath()
            path.move(to: points[0])
            for i in 1..<points.count { path.line(to: points[i]) }
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            applyDash(to: path, isShape: false)
            path.stroke()
        case .text:
            guard !text.isEmpty else { return }
            (text as NSString).draw(at: startPoint, withAttributes: textAttributes)
        case .mosaic:
            if let img = mosaicImage {
                let f = frame
                guard let ctx = NSGraphicsContext.current?.cgContext else { return }
                ctx.saveGState()
                // flipped view 中绘制 CGImage 需要翻转
                ctx.translateBy(x: f.origin.x, y: f.origin.y + f.height)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: f.width, height: f.height))
                ctx.restoreGState()
            } else {
                drawMosaicPreview()
            }
        }
    }

    /// 拖拽过程中的马赛克预览（半透明灰色笔触）
    private func drawMosaicPreview() {
        guard points.count >= 2 else { return }
        let path = NSBezierPath()
        path.move(to: points[0])
        for i in 1..<points.count { path.line(to: points[i]) }
        path.lineWidth = brushWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor(white: 0.5, alpha: 0.4).setStroke()
        path.stroke()
    }

    private func drawArrow() {
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 0 else { return }

        let arrowLen = max(lineWidth * 5, 14)
        let arrowWidth = arrowLen * 0.45
        let ux = dx / length, uy = dy / length
        let px = -uy, py = ux

        // 三角形底边中点：线条终止于此，避免线头穿出箭尖
        let baseCenter = NSPoint(x: endPoint.x - ux * arrowLen,
                                 y: endPoint.y - uy * arrowLen)

        let linePath = NSBezierPath()
        linePath.move(to: startPoint)
        linePath.line(to: baseCenter)
        linePath.lineWidth = lineWidth
        linePath.lineCapStyle = .round
        applyDash(to: linePath, isShape: false)
        linePath.stroke()

        let tip = endPoint
        let left = NSPoint(x: tip.x - ux * arrowLen + px * arrowWidth,
                           y: tip.y - uy * arrowLen + py * arrowWidth)
        let right = NSPoint(x: tip.x - ux * arrowLen - px * arrowWidth,
                            y: tip.y - uy * arrowLen - py * arrowWidth)

        let arrow = NSBezierPath()
        arrow.move(to: tip)
        arrow.line(to: left)
        arrow.line(to: right)
        arrow.close()
        arrow.fill()
    }

    /// isShape: 矩形/椭圆用更大缩放，虚线段更明显
    private func applyDash(to path: NSBezierPath, isShape: Bool) {
        guard !dashPattern.isEmpty else { return }
        let scale = (isShape ? 2.0 : 1.0) * max(1.0, lineWidth * 0.7)
        let scaled = dashPattern.map { $0 * scale }
        path.setLineDash(scaled, count: scaled.count, phase: 0)
    }

    // MARK: - 命中检测

    func hitTest(point: NSPoint) -> Bool {
        let tolerance = max(lineWidth * 2, 8)

        switch tool {
        case .arrow, .line:
            return distanceToSegment(point: point, a: startPoint, b: endPoint) < tolerance
        case .rect:
            let r = normalizedRect
            let outer = r.insetBy(dx: -tolerance, dy: -tolerance)
            let inner = r.insetBy(dx: tolerance, dy: tolerance)
            return outer.contains(point) && (inner.isEmpty || !inner.contains(point))
        case .ellipse:
            return frame.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .freehand:
            for i in 1..<points.count {
                if distanceToSegment(point: point, a: points[i-1], b: points[i]) < tolerance {
                    return true
                }
            }
            return false
        case .mosaic:
            let mosaicTolerance = brushWidth / 2 + 4
            for i in 1..<points.count {
                if distanceToSegment(point: point, a: points[i-1], b: points[i]) < mosaicTolerance {
                    return true
                }
            }
            return false
        case .text:
            return frame.insetBy(dx: -4, dy: -4).contains(point)
        }
    }

    private func distanceToSegment(point: NSPoint, a: NSPoint, b: NSPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lenSq))
        let proj = NSPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(point.x - proj.x, point.y - proj.y)
    }

    // MARK: - 移动/缩放

    func move(by delta: NSSize) {
        switch tool {
        case .arrow, .line, .rect, .ellipse:
            startPoint.x += delta.width; startPoint.y += delta.height
            endPoint.x += delta.width; endPoint.y += delta.height
        case .freehand, .mosaic:
            for i in 0..<points.count {
                points[i].x += delta.width; points[i].y += delta.height
            }
        case .text:
            startPoint.x += delta.width; startPoint.y += delta.height
        }
    }

    /// 根据新 frame 缩放标记
    func resize(to newFrame: NSRect) {
        let old = frame
        guard old.width > 0, old.height > 0 else { return }
        let sx = newFrame.width / old.width
        let sy = newFrame.height / old.height

        switch tool {
        case .arrow, .line, .rect, .ellipse:
            startPoint = scaled(startPoint, from: old, to: newFrame, sx: sx, sy: sy)
            endPoint = scaled(endPoint, from: old, to: newFrame, sx: sx, sy: sy)
        case .freehand, .mosaic:
            for i in 0..<points.count {
                points[i] = scaled(points[i], from: old, to: newFrame, sx: sx, sy: sy)
            }
        case .text:
            startPoint = newFrame.origin
        }
    }

    private func scaled(_ p: NSPoint, from old: NSRect, to new: NSRect, sx: CGFloat, sy: CGFloat) -> NSPoint {
        NSPoint(x: new.origin.x + (p.x - old.origin.x) * sx,
                y: new.origin.y + (p.y - old.origin.y) * sy)
    }
}
