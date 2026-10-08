import Cocoa

class AnnotationEditorWindow: NSWindow {

    private var originalImage: CGImage
    private let canvas: AnnotationCanvas
    private let annotationToolbar: AnnotationToolbar
    private var escKeyMonitor: Any?
    var onClose: (() -> Void)?
    /// 用户确认后交出合成图。直接关窗口不会调用。
    var onSave: ((CGImage) -> Void)?

    /// anchor 为截图在屏幕上的 AppKit 矩形。窗口尽量盖住这块区域，标注就留在选区上。
    init(image: CGImage, screen: NSScreen, anchor: NSRect? = nil) {
        self.originalImage = image

        let visible = screen.visibleFrame
        let maxW = visible.width * 0.9
        let maxH = visible.height * 0.9
        let imgW = CGFloat(image.width) / screen.backingScaleFactor
        let imgH = CGFloat(image.height) / screen.backingScaleFactor
        let scale = min(1.0, min(maxW / imgW, (maxH - AnnotationToolbar.toolbarHeight) / imgH))
        let canvasW = imgW * scale
        let canvasH = imgH * scale
        let winW = canvasW
        let winH = canvasH + AnnotationToolbar.toolbarHeight

        // 画布在内容区底部。让画布中心对齐选区；没有选区时在可见区域内居中。
        let origin: NSPoint
        if let anchor {
            origin = NSPoint(x: anchor.midX - winW / 2, y: anchor.midY - canvasH / 2)
        } else {
            origin = NSPoint(x: visible.midX - winW / 2, y: visible.midY - winH / 2)
        }
        let winRect = NSRect(x: origin.x, y: origin.y, width: winW, height: winH)

        self.annotationToolbar = AnnotationToolbar(frame: NSRect(x: 0, y: 0, width: winW, height: AnnotationToolbar.toolbarHeight))
        self.canvas = AnnotationCanvas(frame: NSRect(x: 0, y: 0, width: canvasW, height: canvasH))

        super.init(
            contentRect: winRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.title = "Screenshot Markup"
        self.minSize = NSSize(width: 240, height: 160)
        self.isReleasedWhenClosed = false

        canvas.backgroundImage = image
        canvas.onToolChangeRequested = { [weak self] tool in
            self?.annotationToolbar.selectTool(tool)
        }
        canvas.onApplyCrop = { [weak self] rect in
            self?.applyCrop(rect: rect)
        }
        canvas.onRequestFinish = { [weak self] in
            self?.saveAndClose()
        }
        annotationToolbar.delegate = self

        // 布局：顶部工具栏 + 下方画布（包裹在 ScrollView 中）
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: winW, height: winH))
        contentView.wantsLayer = true

        annotationToolbar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(annotationToolbar)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor
        contentView.addSubview(scrollView)

        self.contentView = contentView

        NSLayoutConstraint.activate([
            annotationToolbar.topAnchor.constraint(equalTo: contentView.topAnchor),
            annotationToolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            annotationToolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            annotationToolbar.heightAnchor.constraint(equalToConstant: AnnotationToolbar.toolbarHeight),

            scrollView.topAnchor.constraint(equalTo: annotationToolbar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        // canvas 尺寸 = 逻辑像素尺寸
        canvas.setFrameSize(NSSize(width: imgW, height: imgH))

        self.delegate = self
        clampIntoVisibleFrame(visible)

        // Esc / Enter：非编辑态时也能响应（如焦点在工具栏）
        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isKeyWindow else { return event }
            if event.keyCode == 53 {
                self.canvas.performEscapeAction()
                return nil
            }
            if event.keyCode == 36 {
                if self.canvas.confirmCropPreviewIfNeeded() { return nil }
                if self.canvas.isEditingText { return event }
                self.saveAndClose()
                return nil
            }
            return event
        }
    }

    /// contentRect 不含标题栏，初始化后再把整窗（含标题栏）收进可见区域。
    private func clampIntoVisibleFrame(_ visible: NSRect) {
        var frame = self.frame
        if frame.width > visible.width { frame.size.width = visible.width }
        if frame.height > visible.height { frame.size.height = visible.height }
        if frame.maxX > visible.maxX { frame.origin.x -= frame.maxX - visible.maxX }
        if frame.minX < visible.minX { frame.origin.x = visible.minX }
        if frame.maxY > visible.maxY { frame.origin.y -= frame.maxY - visible.maxY }
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        setFrame(frame, display: false)
    }

    deinit {
        if let m = escKeyMonitor { NSEvent.removeMonitor(m) }
    }

    /// 合成标记后的图像
    func renderCompositeImage() -> CGImage? {
        let w = originalImage.width
        let h = originalImage.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // 绘制原图
        ctx.draw(originalImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        // 计算 canvas 到原图的缩放因子
        let scaleX = CGFloat(w) / canvas.frame.width
        let scaleY = CGFloat(h) / canvas.frame.height

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        for ann in canvas.annotations {
            ctx.saveGState()
            // CGContext 原点在左下角，需要翻转 Y 坐标
            ctx.scaleBy(x: scaleX, y: scaleY)
            // 翻转回 flipped view 坐标
            ctx.translateBy(x: 0, y: canvas.frame.height)
            ctx.scaleBy(x: 1, y: -1)
            ann.draw()
            ctx.restoreGState()
        }

        NSGraphicsContext.restoreGraphicsState()

        return ctx.makeImage()
    }

    private var shouldSave = false

    private func applyCrop(rect: NSRect) {
        // 画布是左上角原点。CGImage.cropping 与区域截图、马赛克一样按像素自上而下取，不能再翻转 Y。
        let scaleX = CGFloat(originalImage.width) / max(canvas.bounds.width, 1)
        let scaleY = CGFloat(originalImage.height) / max(canvas.bounds.height, 1)
        var pixelRect = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral
        let imageBounds = CGRect(x: 0, y: 0, width: originalImage.width, height: originalImage.height)
        pixelRect = pixelRect.intersection(imageBounds)
        guard pixelRect.width >= 2, pixelRect.height >= 2,
              let cropped = originalImage.cropping(to: pixelRect) else { return }

        originalImage = cropped
        canvas.backgroundImage = cropped

        let newW = CGFloat(cropped.width) / scaleX
        let newH = CGFloat(cropped.height) / scaleY
        canvas.setFrameSize(NSSize(width: newW, height: newH))
        canvas.needsDisplay = true

        canvas.annotations.removeAll { !$0.frame.intersects(rect) }
        for ann in canvas.annotations {
            ann.move(by: NSSize(width: -rect.origin.x, height: -rect.origin.y))
        }

        annotationToolbar.selectTool(.arrow)
    }

    private func saveAndClose() {
        canvas.commitTextEditingIfNeeded()
        shouldSave = true
        close()
    }

    private func discardAndClose() {
        shouldSave = false
        close()
    }
}

// MARK: - NSWindowDelegate

extension AnnotationEditorWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if shouldSave, let composite = renderCompositeImage() {
            onSave?(composite)
        }
        onClose?()
    }
}

// MARK: - AnnotationToolbarDelegate

extension AnnotationEditorWindow: AnnotationToolbarDelegate {
    func toolbarDidSelectTool(_ tool: AnnotationTool) {
        canvas.currentTool = tool
    }

    func toolbarDidSelectColor(_ color: NSColor) {
        canvas.currentColor = color
        canvas.updateSelectedAnnotationStyle()
    }

    func toolbarDidSelectLineWidth(_ width: CGFloat) {
        canvas.currentLineWidth = width
        canvas.updateSelectedAnnotationStyle()
    }

    func toolbarDidSelectDashPattern(_ pattern: [CGFloat]) {
        canvas.currentDashPattern = pattern
        canvas.updateSelectedAnnotationStyle()
    }

    func toolbarDidSelectCropAspectRatio(_ ratio: CropAspectRatio?) {
        canvas.currentCropAspectRatio = ratio ?? .free
    }

    func toolbarDidSelectFontName(_ name: String) {
        canvas.currentFontName = name
        canvas.updateSelectedAnnotationStyle()
    }

    func toolbarDidSelectFontSize(_ size: CGFloat) {
        canvas.currentFontSize = size
        canvas.updateSelectedAnnotationStyle()
    }

    func toolbarDidToggleBold() {
        canvas.isBold.toggle()
        canvas.updateSelectedAnnotationStyle()
    }

    func toolbarDidToggleItalic() {
        canvas.isItalic.toggle()
        canvas.updateSelectedAnnotationStyle()
    }

    func toolbarDidUndo() {
        discardAndClose()
    }

    func toolbarDidDone() {
        saveAndClose()
    }
}
