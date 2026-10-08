import Cocoa

class AnnotationEditorWindow: NSWindow {

    private var originalImage: CGImage
    private let canvas: AnnotationCanvas
    private let annotationToolbar: AnnotationToolbar
    private let hostScreen: NSScreen
    /// 画布显示尺寸。窗口内容跟着这两条约束走，工具栏不能把图片拉变形。
    private var canvasWidthConstraint: NSLayoutConstraint!
    private var canvasHeightConstraint: NSLayoutConstraint!
    private var escKeyMonitor: Any?
    var onClose: (() -> Void)?
    /// 用户确认后交出合成图。直接关窗口不会调用。
    var onSave: ((CGImage) -> Void)?

    /// 预览窗口按图片比例在屏幕正中打开。anchor 保留是为了兼容调用方，不参与布局。
    init(image: CGImage, screen: NSScreen, anchor: NSRect? = nil) {
        self.originalImage = image
        self.hostScreen = screen
        _ = anchor

        let fitted = Self.fittedContentSize(for: image, on: screen)
        let canvasW = fitted.width
        let canvasH = fitted.height
        let winW = canvasW
        let winH = canvasH + AnnotationToolbar.toolbarHeight
        let visible = screen.visibleFrame
        let winRect = NSRect(
            x: visible.midX - winW / 2,
            y: visible.midY - winH / 2,
            width: winW,
            height: winH
        )

        self.annotationToolbar = AnnotationToolbar(frame: NSRect(x: 0, y: 0, width: winW, height: AnnotationToolbar.toolbarHeight))
        self.canvas = AnnotationCanvas(frame: NSRect(x: 0, y: 0, width: canvasW, height: canvasH))

        super.init(
            contentRect: winRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = "Screenshot Markup"
        self.isReleasedWhenClosed = false
        let locked = frameRect(forContentRect: NSRect(origin: .zero, size: NSSize(width: winW, height: winH))).size
        self.minSize = locked
        self.maxSize = locked

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

        // 工具栏在上，画布铺满剩余区域，尺寸与图片显示大小一致。
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: winW, height: winH))
        contentView.wantsLayer = true

        annotationToolbar.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(annotationToolbar)
        contentView.addSubview(canvas)

        self.contentView = contentView

        canvasWidthConstraint = canvas.widthAnchor.constraint(equalToConstant: canvasW)
        canvasHeightConstraint = canvas.heightAnchor.constraint(equalToConstant: canvasH)
        // 贴边约束低于宽高，窗口被工具栏撑宽时画布保持图片比例，而不是跟着拉变形。
        let canvasTrailing = canvas.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        let canvasBottom = canvas.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        canvasTrailing.priority = .defaultHigh
        canvasBottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            annotationToolbar.topAnchor.constraint(equalTo: contentView.topAnchor),
            annotationToolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            annotationToolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            annotationToolbar.heightAnchor.constraint(equalToConstant: AnnotationToolbar.toolbarHeight),

            canvas.topAnchor.constraint(equalTo: annotationToolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            canvasTrailing,
            canvasBottom,
            canvasWidthConstraint,
            canvasHeightConstraint,
        ])

        self.delegate = self
        centerInVisibleFrame()

        // Esc / Enter：非编辑态时也能响应（如焦点在工具栏）
        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isKeyWindow else { return event }
            if event.keyCode == 53 {
                self.canvas.performEscapeAction()
                return nil
            }
            if event.keyCode == 36 {
                if self.canvas.confirmCropPreviewIfNeeded() { return nil }
                if self.canvas.isEditingText {
                    self.canvas.commitTextEditingIfNeeded()
                    return nil
                }
                self.saveAndClose()
                return nil
            }
            return event
        }
    }

    /// 把图片缩放到屏幕可见区域的 90% 以内，返回画布点尺寸（不含工具栏）。
    private static func fittedContentSize(for image: CGImage, on screen: NSScreen) -> NSSize {
        let visible = screen.visibleFrame
        let imgW = max(CGFloat(image.width) / screen.backingScaleFactor, 1)
        let imgH = max(CGFloat(image.height) / screen.backingScaleFactor, 1)
        let maxW = visible.width * 0.9
        let maxH = max((visible.height - 28) * 0.9 - AnnotationToolbar.toolbarHeight, 1)
        let fit = min(1, min(maxW / imgW, maxH / imgH))
        return NSSize(width: imgW * fit, height: imgH * fit)
    }

    /// 把窗口内容锁成「画布 + 工具栏」。先放开最小尺寸，否则窗口缩不下去，图片会被拉变形。
    private func lockWindow(canvasSize: NSSize) {
        canvasWidthConstraint.constant = max(canvasSize.width, 1)
        canvasHeightConstraint.constant = max(canvasSize.height, 1)
        let content = NSSize(
            width: canvasWidthConstraint.constant,
            height: canvasHeightConstraint.constant + AnnotationToolbar.toolbarHeight
        )
        let target = frameRect(forContentRect: NSRect(origin: .zero, size: content)).size
        // 上限先收到目标尺寸，避免工具栏的固有宽度把窗口重新撑宽。
        minSize = NSSize(width: 1, height: 1)
        maxSize = target
        setContentSize(content)
        minSize = frame.size
        maxSize = frame.size
        centerInVisibleFrame()
    }

    private func centerInVisibleFrame() {
        let visible = hostScreen.visibleFrame
        var origin = NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.midY - frame.height / 2
        )
        origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)
        setFrameOrigin(origin)
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
        // 用当前画布的实际显示比例换算。宽高同一比例，裁出来的像素和选区一致。
        let scale = CGFloat(originalImage.width) / max(canvas.bounds.width, 1)
        var pixelRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral
        let imageBounds = CGRect(x: 0, y: 0, width: originalImage.width, height: originalImage.height)
        pixelRect = pixelRect.intersection(imageBounds)
        guard pixelRect.width >= 2, pixelRect.height >= 2,
              let cropped = originalImage.cropping(to: pixelRect) else { return }

        originalImage = cropped
        canvas.backgroundImage = cropped

        canvas.annotations.removeAll { !$0.frame.intersects(rect) }
        for ann in canvas.annotations {
            ann.move(by: NSSize(width: -rect.origin.x, height: -rect.origin.y))
        }

        lockWindow(canvasSize: NSSize(
            width: CGFloat(cropped.width) / scale,
            height: CGFloat(cropped.height) / scale
        ))
        canvas.needsDisplay = true
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
