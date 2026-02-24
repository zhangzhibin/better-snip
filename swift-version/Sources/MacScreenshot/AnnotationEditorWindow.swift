import Cocoa

class AnnotationEditorWindow: NSWindow {

    private var originalImage: CGImage
    private let canvas: AnnotationCanvas
    private let annotationToolbar: AnnotationToolbar
    private var escKeyMonitor: Any?
    var onClose: (() -> Void)?

    init(image: CGImage, screen: NSScreen) {
        self.originalImage = image

        // 计算窗口尺寸：适配截图大小，限制不超过屏幕 80%
        let screenFrame = screen.visibleFrame
        let maxW = screenFrame.width * 0.8
        let maxH = screenFrame.height * 0.8
        let imgW = CGFloat(image.width) / screen.backingScaleFactor
        let imgH = CGFloat(image.height) / screen.backingScaleFactor
        let scale = min(1.0, min(maxW / imgW, (maxH - AnnotationToolbar.toolbarHeight) / imgH))
        let canvasW = imgW * scale
        let canvasH = imgH * scale
        let winW = canvasW
        let winH = canvasH + AnnotationToolbar.toolbarHeight

        // 窗口居中
        let winX = screenFrame.origin.x + (screenFrame.width - winW) / 2
        let winY = screenFrame.origin.y + (screenFrame.height - winH) / 2
        let winRect = NSRect(x: winX, y: winY, width: winW, height: winH)

        self.annotationToolbar = AnnotationToolbar(frame: NSRect(x: 0, y: 0, width: winW, height: AnnotationToolbar.toolbarHeight))
        self.canvas = AnnotationCanvas(frame: NSRect(x: 0, y: 0, width: canvasW, height: canvasH))

        super.init(
            contentRect: winRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.title = "Screenshot Markup"
        self.minSize = NSSize(width: 400, height: 300)
        self.isReleasedWhenClosed = false

        canvas.backgroundImage = image
        canvas.onToolChangeRequested = { [weak self] tool in
            self?.annotationToolbar.selectTool(tool)
        }
        canvas.onApplyCrop = { [weak self] rect in
            self?.applyCrop(rect: rect)
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

        // Esc / Enter：非编辑态时也能响应（如焦点在工具栏）
        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isKeyWindow else { return event }
            if event.keyCode == 53 {
                self.canvas.performEscapeAction()
                return nil
            }
            if event.keyCode == 36, self.canvas.confirmCropPreviewIfNeeded() {
                return nil
            }
            return event
        }
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
        let scale = CGFloat(originalImage.width) / canvas.frame.width
        let canvasH = canvas.frame.height
        // CGImage 原点在左下角，canvas 为左上角原点，需翻转 Y
        let pixelRect = CGRect(
            x: rect.origin.x * scale,
            y: (canvasH - rect.origin.y - rect.height) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral
        guard pixelRect.width >= 2, pixelRect.height >= 2,
              let cropped = originalImage.cropping(to: pixelRect) else { return }

        originalImage = cropped
        canvas.backgroundImage = cropped

        let newW = CGFloat(cropped.width) / scale
        let newH = CGFloat(cropped.height) / scale
        canvas.setFrameSize(NSSize(width: newW, height: newH))

        canvas.annotations.removeAll { !$0.frame.intersects(rect) }
        for ann in canvas.annotations {
            ann.move(by: NSSize(width: -rect.origin.x, height: -rect.origin.y))
        }

        annotationToolbar.selectTool(.arrow)
    }

    private func saveAndClose() {
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
        if shouldSave {
            if let composite = renderCompositeImage() {
                _ = ScreenCapture.writeToClipboard(composite)
            }
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
