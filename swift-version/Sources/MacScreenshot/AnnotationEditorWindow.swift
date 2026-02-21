import Cocoa

class AnnotationEditorWindow: NSWindow {

    private let originalImage: CGImage
    private let canvas: AnnotationCanvas
    private let annotationToolbar: AnnotationToolbar
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

    private func closeEditor() {
        if !canvas.annotations.isEmpty {
            if let composite = renderCompositeImage() {
                _ = ScreenCapture.writeToClipboard(composite)
            }
        }
        onClose?()
    }
}

// MARK: - NSWindowDelegate

extension AnnotationEditorWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        closeEditor()
    }
}

// MARK: - AnnotationToolbarDelegate

extension AnnotationEditorWindow: AnnotationToolbarDelegate {
    func toolbarDidSelectTool(_ tool: AnnotationTool) {
        canvas.currentTool = tool
    }

    func toolbarDidSelectColor(_ color: NSColor) {
        canvas.currentColor = color
    }

    func toolbarDidSelectLineWidth(_ width: CGFloat) {
        canvas.currentLineWidth = width
    }

    func toolbarDidSelectFontName(_ name: String) {
        canvas.currentFontName = name
    }

    func toolbarDidSelectFontSize(_ size: CGFloat) {
        canvas.currentFontSize = size
    }

    func toolbarDidToggleBold() {
        canvas.isBold.toggle()
    }

    func toolbarDidToggleItalic() {
        canvas.isItalic.toggle()
    }

    func toolbarDidUndo() {
        canvas.undo()
    }

    func toolbarDidDone() {
        close()
    }
}
