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

        // 工具栏在上。画布按图片尺寸居中；图片窄于工具栏时，两侧留出窗口底色，不拉变形。
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: winW, height: winH))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        annotationToolbar.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(annotationToolbar)
        contentView.addSubview(canvas)

        self.contentView = contentView

        canvasWidthConstraint = canvas.widthAnchor.constraint(equalToConstant: canvasW)
        canvasHeightConstraint = canvas.heightAnchor.constraint(equalToConstant: canvasH)
        NSLayoutConstraint.activate([
            annotationToolbar.topAnchor.constraint(equalTo: contentView.topAnchor),
            annotationToolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            annotationToolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            annotationToolbar.heightAnchor.constraint(equalToConstant: AnnotationToolbar.toolbarHeight),

            canvas.topAnchor.constraint(equalTo: annotationToolbar.bottomAnchor),
            canvas.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            canvas.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            canvasWidthConstraint,
            canvasHeightConstraint,
        ])

        self.delegate = self
        lockWindow(canvasSize: NSSize(width: canvasW, height: canvasH))

        // Esc 丢弃本次截图，与关闭按钮相同。Enter 确认保存。
        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isKeyWindow else { return event }
            if event.keyCode == 53 {
                self.discardAndClose()
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

    /// 把窗口内容锁成「画布 + 工具栏」。图片窄于工具栏时加宽到能放下按钮，画布仍按图片比例居中。
    private func lockWindow(canvasSize: NSSize) {
        applyContentSize(contentSize(forCanvas: canvasSize), recenter: true)
    }

    /// 切换工具露出更多控件时加宽窗口，不移动窗口、不改变画布比例。
    private func ensureToolbarFits() {
        let content = contentSize(forCanvas: NSSize(
            width: canvasWidthConstraint.constant,
            height: canvasHeightConstraint.constant
        ))
        applyContentSize(content, recenter: false)
    }

    private func contentSize(forCanvas canvasSize: NSSize) -> NSSize {
        canvasWidthConstraint.constant = max(canvasSize.width, 1)
        canvasHeightConstraint.constant = max(canvasSize.height, 1)
        annotationToolbar.layoutSubtreeIfNeeded()
        return NSSize(
            width: max(canvasWidthConstraint.constant, annotationToolbar.minimumContentWidth),
            height: canvasHeightConstraint.constant + AnnotationToolbar.toolbarHeight
        )
    }

    private func applyContentSize(_ content: NSSize, recenter: Bool) {
        let target = frameRect(forContentRect: NSRect(origin: .zero, size: content)).size
        minSize = NSSize(width: 1, height: 1)
        maxSize = target
        setContentSize(content)
        minSize = frame.size
        maxSize = frame.size
        if recenter {
            centerInVisibleFrame()
        }
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
        ensureToolbarFits()
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
