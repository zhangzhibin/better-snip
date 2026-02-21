import Cocoa
import CoreImage

/// 缩放手柄位置
enum ResizeHandle: Int, CaseIterable {
    case topLeft, topCenter, topRight
    case middleLeft, middleRight
    case bottomLeft, bottomCenter, bottomRight
}

class AnnotationCanvas: NSView {

    // MARK: - 公共属性

    var backgroundImage: CGImage?
    var annotations: [Annotation] = []
    var onAnnotationsChanged: (() -> Void)?

    var currentTool: AnnotationTool = .arrow
    var currentColor: NSColor = .systemRed
    var currentLineWidth: CGFloat = 2.5
    var currentFontName: String = "system"
    var currentFontSize: CGFloat = 16
    var isBold: Bool = false
    var isItalic: Bool = false

    // MARK: - 状态

    private enum State {
        case idle
        case drawing
        case selected(Annotation)
        case moving(Annotation, NSPoint)
        case resizing(Annotation, ResizeHandle, NSRect)
        case editingText(Annotation)
    }

    private var state: State = .idle
    private var drawingAnnotation: Annotation?
    private var textField: NSTextField?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private let handleSize: CGFloat = 8

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current else { return }

        // 绘制背景图
        if let bg = backgroundImage {
            let cgCtx = ctx.cgContext
            cgCtx.saveGState()
            cgCtx.translateBy(x: 0, y: bounds.height)
            cgCtx.scaleBy(x: 1, y: -1)
            cgCtx.draw(bg, in: bounds)
            cgCtx.restoreGState()
        }

        // 绘制所有已完成标记
        for annotation in annotations {
            annotation.draw()
        }

        // 绘制正在创建的标记（虚线预览）
        if let drawing = drawingAnnotation {
            NSGraphicsContext.saveGraphicsState()
            drawing.draw()
            NSGraphicsContext.restoreGraphicsState()
        }

        // 绘制选中标记的手柄
        if case .selected(let ann) = state {
            drawHandles(for: ann)
        } else if case .moving(let ann, _) = state {
            drawHandles(for: ann)
        } else if case .resizing(let ann, _, _) = state {
            drawHandles(for: ann)
        }
    }

    private func drawHandles(for annotation: Annotation) {
        let frame = annotation.frame
        guard frame.width > 0 || frame.height > 0 else { return }

        // 选中边框
        let borderPath = NSBezierPath(rect: frame)
        borderPath.lineWidth = 1
        NSColor.controlAccentColor.withAlphaComponent(0.5).setStroke()
        let dashPattern: [CGFloat] = [4, 4]
        borderPath.setLineDash(dashPattern, count: 2, phase: 0)
        borderPath.stroke()

        // 8 个手柄
        NSColor.white.setFill()
        NSColor.controlAccentColor.setStroke()
        for handle in ResizeHandle.allCases {
            let rect = handleRect(for: handle, in: frame)
            let path = NSBezierPath(ovalIn: rect)
            path.fill()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func handleRect(for handle: ResizeHandle, in frame: NSRect) -> NSRect {
        let s = handleSize
        let hs = s / 2
        let midX = frame.midX, midY = frame.midY
        let pt: NSPoint
        switch handle {
        case .topLeft:      pt = NSPoint(x: frame.minX, y: frame.minY)
        case .topCenter:    pt = NSPoint(x: midX, y: frame.minY)
        case .topRight:     pt = NSPoint(x: frame.maxX, y: frame.minY)
        case .middleLeft:   pt = NSPoint(x: frame.minX, y: midY)
        case .middleRight:  pt = NSPoint(x: frame.maxX, y: midY)
        case .bottomLeft:   pt = NSPoint(x: frame.minX, y: frame.maxY)
        case .bottomCenter: pt = NSPoint(x: midX, y: frame.maxY)
        case .bottomRight:  pt = NSPoint(x: frame.maxX, y: frame.maxY)
        }
        return NSRect(x: pt.x - hs, y: pt.y - hs, width: s, height: s)
    }

    /// 检测点击在哪个手柄上
    private func hitHandle(point: NSPoint, in frame: NSRect) -> ResizeHandle? {
        for handle in ResizeHandle.allCases {
            let rect = handleRect(for: handle, in: frame).insetBy(dx: -4, dy: -4)
            if rect.contains(point) { return handle }
        }
        return nil
    }

    // MARK: - 鼠标事件

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // 如果正在编辑文字，先完成编辑
        if case .editingText(let ann) = state {
            finishTextEditing(ann)
        }

        // 检查是否点击在选中标记的手柄上
        if case .selected(let ann) = state {
            if let handle = hitHandle(point: point, in: ann.frame) {
                state = .resizing(ann, handle, ann.frame)
                return
            }
        }

        // 检查是否点击在已有标记上 → 选中
        for annotation in annotations.reversed() {
            if annotation.hitTest(point: point) {
                state = .selected(annotation)
                if currentTool == .text && annotation.tool == .text {
                    startTextEditing(annotation)
                    return
                }
                setNeedsDisplay(bounds)
                return
            }
        }

        // 没有命中 → 开始绘制
        state = .idle
        if currentTool == .text {
            let ann = makeAnnotation()
            ann.startPoint = point
            ann.text = "Text"
            annotations.append(ann)
            onAnnotationsChanged?()
            startTextEditing(ann)
            return
        }

        let ann = makeAnnotation()
        ann.startPoint = point
        ann.endPoint = point
        if currentTool == .freehand || currentTool == .mosaic {
            ann.points = [point]
        }
        if currentTool == .mosaic {
            ann.brushWidth = mosaicBrushWidth
        }
        drawingAnnotation = ann
        state = .drawing
        setNeedsDisplay(bounds)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch state {
        case .drawing:
            guard let ann = drawingAnnotation else { return }
            if ann.tool == .freehand || ann.tool == .mosaic {
                ann.points.append(point)
            } else {
                ann.endPoint = point
            }
            setNeedsDisplay(bounds)

        case .selected(let ann):
            // 开始移动
            state = .moving(ann, point)

        case .moving(let ann, let lastPoint):
            let dx = point.x - lastPoint.x
            let dy = point.y - lastPoint.y
            ann.move(by: NSSize(width: dx, height: dy))
            state = .moving(ann, point)
            onAnnotationsChanged?()
            setNeedsDisplay(bounds)

        case .resizing(let ann, let handle, let originalFrame):
            let newFrame = resizedFrame(original: originalFrame, handle: handle, currentPoint: point)
            ann.resize(to: newFrame)
            state = .resizing(ann, handle, ann.frame)
            onAnnotationsChanged?()
            setNeedsDisplay(bounds)

        default:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch state {
        case .drawing:
            if let ann = drawingAnnotation {
                if ann.tool == .mosaic {
                    if ann.points.count >= 2 {
                        generateMosaicImage(for: ann)
                        annotations.append(ann)
                        onAnnotationsChanged?()
                    }
                } else {
                    let dx = abs(ann.endPoint.x - ann.startPoint.x)
                    let dy = abs(ann.endPoint.y - ann.startPoint.y)
                    let minSize: CGFloat = ann.tool == .freehand ? 2 : 4
                    if dx > minSize || dy > minSize || (ann.tool == .freehand && ann.points.count > 2) {
                        annotations.append(ann)
                        onAnnotationsChanged?()
                    }
                }
            }
            drawingAnnotation = nil
            state = .idle
            setNeedsDisplay(bounds)

        case .moving(let ann, _):
            state = .selected(ann)
            setNeedsDisplay(bounds)

        case .resizing(let ann, _, _):
            state = .selected(ann)
            setNeedsDisplay(bounds)

        default:
            break
        }
    }

    // MARK: - 键盘事件

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { // Delete / Forward Delete
            if case .selected(let ann) = state {
                deleteAnnotation(ann)
                return
            }
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            undo()
            return
        }
        if event.keyCode == 53 { // Escape
            if case .selected = state {
                state = .idle
                setNeedsDisplay(bounds)
                return
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - 缩放计算

    private func resizedFrame(original: NSRect, handle: ResizeHandle, currentPoint: NSPoint) -> NSRect {
        var newFrame = original
        switch handle {
        case .topLeft:
            newFrame.origin.x = currentPoint.x
            newFrame.origin.y = currentPoint.y
            newFrame.size.width = original.maxX - currentPoint.x
            newFrame.size.height = original.maxY - currentPoint.y
        case .topCenter:
            newFrame.origin.y = currentPoint.y
            newFrame.size.height = original.maxY - currentPoint.y
        case .topRight:
            newFrame.size.width = currentPoint.x - original.minX
            newFrame.origin.y = currentPoint.y
            newFrame.size.height = original.maxY - currentPoint.y
        case .middleLeft:
            newFrame.origin.x = currentPoint.x
            newFrame.size.width = original.maxX - currentPoint.x
        case .middleRight:
            newFrame.size.width = currentPoint.x - original.minX
        case .bottomLeft:
            newFrame.origin.x = currentPoint.x
            newFrame.size.width = original.maxX - currentPoint.x
            newFrame.size.height = currentPoint.y - original.minY
        case .bottomCenter:
            newFrame.size.height = currentPoint.y - original.minY
        case .bottomRight:
            newFrame.size.width = currentPoint.x - original.minX
            newFrame.size.height = currentPoint.y - original.minY
        }
        // 保证最小尺寸
        if newFrame.width < 10 { newFrame.size.width = 10 }
        if newFrame.height < 10 { newFrame.size.height = 10 }
        return newFrame
    }

    // MARK: - 文字编辑

    private func startTextEditing(_ annotation: Annotation) {
        state = .editingText(annotation)

        let frame = annotation.frame
        let tf = NSTextField(frame: NSRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: max(frame.width, 120),
            height: max(frame.height, annotation.font.pointSize + 8)
        ))
        tf.font = annotation.font
        tf.textColor = annotation.color
        tf.stringValue = annotation.text
        tf.isBezeled = true
        tf.bezelStyle = .roundedBezel
        tf.isEditable = true
        tf.drawsBackground = true
        tf.backgroundColor = .white
        tf.focusRingType = .default
        tf.target = self
        tf.action = #selector(textFieldAction(_:))
        addSubview(tf)
        window?.makeFirstResponder(tf)
        textField = tf
    }

    @objc private func textFieldAction(_ sender: NSTextField) {
        if case .editingText(let ann) = state {
            finishTextEditing(ann)
        }
    }

    private func finishTextEditing(_ annotation: Annotation) {
        if let tf = textField {
            annotation.text = tf.stringValue
            tf.removeFromSuperview()
            textField = nil
        }
        if annotation.text.isEmpty {
            deleteAnnotation(annotation)
        } else {
            onAnnotationsChanged?()
        }
        state = .idle
        setNeedsDisplay(bounds)
    }

    // MARK: - 操作

    func deleteAnnotation(_ annotation: Annotation) {
        annotations.removeAll { $0 === annotation }
        state = .idle
        onAnnotationsChanged?()
        setNeedsDisplay(bounds)
    }

    func undo() {
        if case .editingText(let ann) = state {
            finishTextEditing(ann)
        }
        if !annotations.isEmpty {
            annotations.removeLast()
            state = .idle
            onAnnotationsChanged?()
            setNeedsDisplay(bounds)
        }
    }

    // MARK: - 马赛克

    /// 线宽到笔刷宽度的映射
    var mosaicBrushWidth: CGFloat {
        switch currentLineWidth {
        case ...1.5:    return 16
        case 1.5...4:   return 28
        default:         return 44
        }
    }

    /// 根据涂抹路径和背景图生成马赛克预渲染图
    private func generateMosaicImage(for annotation: Annotation) {
        guard let bg = backgroundImage, !annotation.points.isEmpty else { return }

        let f = annotation.frame
        guard f.width > 1, f.height > 1 else { return }

        // canvas 点坐标到像素坐标的缩放因子
        let scaleX = CGFloat(bg.width) / bounds.width
        let scaleY = CGFloat(bg.height) / bounds.height

        // 裁剪区域（像素坐标）
        let cropRect = CGRect(
            x: f.origin.x * scaleX,
            y: f.origin.y * scaleY,
            width: f.width * scaleX,
            height: f.height * scaleY
        ).integral

        guard cropRect.width >= 2, cropRect.height >= 2,
              let cropped = bg.cropping(to: cropRect) else { return }

        // CIPixellate 像素化
        let ciImage = CIImage(cgImage: cropped)
        let pixelScale = max(8, max(cropRect.width, cropRect.height) / 12)
        guard let filter = CIFilter(name: "CIPixellate") else { return }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(pixelScale, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)

        let ciCtx = CIContext()
        guard let pixelatedCI = filter.outputImage,
              let pixelatedCG = ciCtx.createCGImage(pixelatedCI, from: ciImage.extent) else { return }

        // 创建最终图像：用笔刷路径做 clip，只保留涂抹区域的马赛克
        let w = Int(cropRect.width), h = Int(cropRect.height)
        guard let maskCtx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        // CGContext 原点在左下角，需要翻转以匹配 flipped view 坐标
        maskCtx.translateBy(x: 0, y: CGFloat(h))
        maskCtx.scaleBy(x: 1, y: -1)

        // 构建笔刷路径（转为裁剪区域的局部像素坐标）
        let brushPath = CGMutablePath()
        let pts = annotation.points
        let bw = annotation.brushWidth * scaleX
        brushPath.move(to: CGPoint(x: (pts[0].x - f.origin.x) * scaleX,
                                   y: (pts[0].y - f.origin.y) * scaleY))
        for i in 1..<pts.count {
            brushPath.addLine(to: CGPoint(x: (pts[i].x - f.origin.x) * scaleX,
                                          y: (pts[i].y - f.origin.y) * scaleY))
        }

        maskCtx.setLineWidth(bw)
        maskCtx.setLineCap(.round)
        maskCtx.setLineJoin(.round)
        maskCtx.addPath(brushPath)
        maskCtx.replacePathWithStrokedPath()
        maskCtx.clip()

        // 在 clip 内绘制像素化图
        maskCtx.translateBy(x: 0, y: CGFloat(h))
        maskCtx.scaleBy(x: 1, y: -1)
        maskCtx.draw(pixelatedCG, in: CGRect(x: 0, y: 0, width: w, height: h))

        annotation.mosaicImage = maskCtx.makeImage()
    }

    // MARK: - Helpers

    private func makeAnnotation() -> Annotation {
        let ann = Annotation(tool: currentTool, color: currentColor, lineWidth: currentLineWidth)
        ann.font = buildFont()
        ann.isBold = isBold
        ann.isItalic = isItalic
        return ann
    }

    func buildFont() -> NSFont {
        var font: NSFont
        switch currentFontName {
        case "mono":
            font = NSFont.monospacedSystemFont(ofSize: currentFontSize, weight: isBold ? .bold : .regular)
        case "serif":
            font = NSFont(name: "Georgia", size: currentFontSize) ?? .systemFont(ofSize: currentFontSize)
        default:
            font = isBold ? .boldSystemFont(ofSize: currentFontSize) : .systemFont(ofSize: currentFontSize)
        }
        if isItalic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }
}
