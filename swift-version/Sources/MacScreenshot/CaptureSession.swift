import Cocoa

/// 一次截图交互：拖选区域，或单击当前悬停的窗口。
/// 先拍下各屏画面，再显示遮罩。这样随后激活应用以接收点击和 Esc 时，截到的仍是按下快捷键时的桌面。
final class CaptureSession {
    var onCapture: ((CGImage, NSScreen, NSRect) -> Void)?
    /// 快照失败时退回实时截图
    var onRegion: ((NSScreen, NSRect) -> Void)?
    var onWindow: ((WindowInfo) -> Void)?
    var onCancel: (() -> Void)?

    private var windows: [CaptureOverlayWindow] = []
    private var snapshots: [CGDirectDisplayID: CGImage] = [:]
    private var localMonitor: Any?
    private var globalMoveMonitor: Any?
    private var globalMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    private var stopped = false
    private var pushedCursor = false

    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var dragScreen: NSScreen?

    func start() {
        for screen in NSScreen.screens {
            let id = ScreenCapture.displayID(for: screen)
            if let image = ScreenCapture.captureFullImage(displayID: id) {
                snapshots[id] = image
            }
        }

        for screen in NSScreen.screens {
            let id = ScreenCapture.displayID(for: screen)
            let window = CaptureOverlayWindow(screen: screen, image: snapshots[id])
            window.overlayView.onMouseDown = { [weak self] in self?.beginDrag() }
            window.overlayView.onMouseDragged = { [weak self] in self?.updateDrag() }
            window.overlayView.onMouseUp = { [weak self] in self?.endDrag() }
            window.overlayView.onEscape = { [weak self] in self?.cancel() }
            windows.append(window)
            window.orderFrontRegardless()
        }
        NSCursor.crosshair.push()
        pushedCursor = true

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]
        ) { [weak self] event in
            guard let self, !self.stopped else { return event }
            switch event.type {
            case .keyDown:
                if event.keyCode == 53 {
                    self.cancel()
                    return nil
                }
            case .mouseMoved:
                self.updateHover()
            case .leftMouseDown:
                self.beginDrag()
            case .leftMouseDragged:
                self.updateDrag()
            case .leftMouseUp:
                self.endDrag()
            default:
                break
            }
            return event
        }

        // 应用未激活时，本地 mouseMoved 不会送达；用全局监听只做高亮。
        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.updateHover()
        }
        // 点击若没落到本应用（激活完成前），全局监听仍能开始选区。落到本窗口时系统不会再回调这里。
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self, !self.stopped else { return }
            switch event.type {
            case .leftMouseDown: self.beginDrag()
            case .leftMouseDragged: self.updateDrag()
            case .leftMouseUp: self.endDrag()
            default: break
            }
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { self?.cancel() }
        }

        // 菜单栏应用默认收不到 Esc。快照已经拍完，这时再激活才能成为按键窗口。
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.focusKeyWindow()
        }

        updateHover()
    }

    func cancel() {
        guard !stopped else { return }
        teardown()
        onCancel?()
    }

    private func teardown() {
        guard !stopped else { return }
        stopped = true
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMoveMonitor { NSEvent.removeMonitor(globalMoveMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        localMonitor = nil
        globalMoveMonitor = nil
        globalMouseMonitor = nil
        globalKeyMonitor = nil
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        if pushedCursor {
            NSCursor.pop()
            pushedCursor = false
        }
    }

    private func beginDrag() {
        let mouse = NSEvent.mouseLocation
        guard let screen = screenContaining(mouse) else { return }
        focus(screen)
        dragScreen = screen
        dragStart = localPoint(mouse, on: screen)
        dragCurrent = dragStart
        clearWindowHighlights()
        showSelection()
    }

    private func updateDrag() {
        guard let screen = dragScreen, dragStart != nil else { return }
        dragCurrent = clamp(localPoint(NSEvent.mouseLocation, on: screen), to: screen)
        showSelection()
    }

    private func endDrag() {
        guard let screen = dragScreen, let start = dragStart, let current = dragCurrent else { return }
        let selection = rect(from: start, to: current)
        dragStart = nil
        dragCurrent = nil
        dragScreen = nil

        if selection.width < 5, selection.height < 5 {
            guard let info = WindowPicker.windowUnderMouse(),
                  let local = windowLocalRect(info, on: screen) else {
                updateHover()
                return
            }
            deliver(localRect: local, on: screen, liveWindow: info)
            return
        }

        deliver(localRect: selection, on: screen, liveWindow: nil)
    }

    private func deliver(localRect: NSRect, on screen: NSScreen, liveWindow: WindowInfo?) {
        let anchor = ScreenCapture.appKitRect(fromFlippedLocal: localRect, on: screen)
        if let image = crop(localRect, on: screen) {
            teardown()
            onCapture?(image, screen, anchor)
            return
        }
        teardown()
        if let liveWindow {
            onWindow?(liveWindow)
        } else {
            onRegion?(screen, localRect)
        }
    }

    private func crop(_ rect: NSRect, on screen: NSScreen) -> CGImage? {
        let id = ScreenCapture.displayID(for: screen)
        guard let full = snapshots[id] else { return nil }
        return ScreenCapture.cropImage(full, rect: rect, scale: screen.backingScaleFactor)
    }

    /// 窗口 bounds 转到该屏幕遮罩的左上角坐标系，并裁到屏幕内。
    private func windowLocalRect(_ info: WindowInfo, on screen: NSScreen) -> NSRect? {
        let appKit = WindowPicker.quartzToAppKit(rect: info.bounds)
        let local = NSRect(
            x: appKit.minX - screen.frame.minX,
            y: screen.frame.maxY - appKit.maxY,
            width: appKit.width,
            height: appKit.height
        )
        let visible = local.intersection(NSRect(origin: .zero, size: screen.frame.size))
        guard visible.width >= 2, visible.height >= 2 else { return nil }
        return visible
    }

    private func focusKeyWindow() {
        guard !stopped else { return }
        let mouse = NSEvent.mouseLocation
        let window = windows.first { $0.targetScreen.frame.contains(mouse) } ?? windows.first
        window?.makeKey()
        if let window {
            window.makeFirstResponder(window.overlayView)
        }
    }

    private func updateHover() {
        guard dragStart == nil, !stopped else { return }
        let mouse = NSEvent.mouseLocation
        let info = WindowPicker.windowUnderMouse()
        for window in windows {
            let screenFrame = window.targetScreen.frame
            window.overlayView.showsHint = screenFrame.contains(mouse)
            guard let info else {
                window.overlayView.windowHighlight = nil
                window.overlayView.needsDisplay = true
                continue
            }
            let appKitRect = WindowPicker.quartzToAppKit(rect: info.bounds)
            guard appKitRect.intersects(screenFrame) else {
                window.overlayView.windowHighlight = nil
                window.overlayView.needsDisplay = true
                continue
            }
            window.overlayView.windowHighlight = NSRect(
                x: appKitRect.origin.x - screenFrame.origin.x,
                y: screenFrame.maxY - appKitRect.maxY,
                width: appKitRect.width,
                height: appKitRect.height
            )
            window.overlayView.needsDisplay = true
        }
    }

    private func showSelection() {
        guard let screen = dragScreen, let start = dragStart, let current = dragCurrent else { return }
        let selection = rect(from: start, to: current)
        let scale = screen.backingScaleFactor
        let label = String(format: "%.0f × %.0f", selection.width * scale, selection.height * scale)
        for window in windows {
            if ScreenCapture.displayID(for: window.targetScreen) == ScreenCapture.displayID(for: screen) {
                window.overlayView.selectionRect = selection
                window.overlayView.sizeLabel = label
            } else {
                window.overlayView.selectionRect = nil
                window.overlayView.sizeLabel = nil
            }
            window.overlayView.windowHighlight = nil
            window.overlayView.needsDisplay = true
        }
    }

    private func clearWindowHighlights() {
        for window in windows {
            window.overlayView.windowHighlight = nil
            window.overlayView.showsHint = false
        }
    }

    private func focus(_ screen: NSScreen) {
        windows.first { $0.targetScreen == screen }?.makeKey()
    }

    private func screenContaining(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.screens.first
    }

    private func localPoint(_ mouse: NSPoint, on screen: NSScreen) -> NSPoint {
        NSPoint(x: mouse.x - screen.frame.minX, y: screen.frame.maxY - mouse.y)
    }

    private func clamp(_ point: NSPoint, to screen: NSScreen) -> NSPoint {
        NSPoint(
            x: min(max(0, point.x), screen.frame.width),
            y: min(max(0, point.y), screen.frame.height)
        )
    }

    private func rect(from a: NSPoint, to b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

private final class CaptureOverlayWindow: NSWindow {
    let targetScreen: NSScreen
    let overlayView: CaptureOverlayView

    init(screen: NSScreen, image: CGImage?) {
        self.targetScreen = screen
        let view = CaptureOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.backgroundImage = image
        self.overlayView = view
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // 不透明窗口才会在整块区域内收到点击。挖空的透明像素会被系统穿透到下层窗口。
        isOpaque = true
        backgroundColor = .black
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        hasShadow = false
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class CaptureOverlayView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var backgroundImage: CGImage?
    override var isOpaque: Bool { backgroundImage != nil }
    override var mouseDownCanMoveWindow: Bool { false }

    var windowHighlight: NSRect?
    var selectionRect: NSRect?
    var sizeLabel: String?
    var showsHint = false
    var onMouseDown: (() -> Void)?
    var onMouseDragged: (() -> Void)?
    var onMouseUp: (() -> Void)?
    var onEscape: (() -> Void)?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?()
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawBackground()
        NSColor(white: 0, alpha: 0.28).setFill()
        bounds.fill()

        if let selection = selectionRect, selection.width >= 1, selection.height >= 1 {
            punch(selection)
            drawManualSelectionBorder(selection)
            if let sizeLabel { drawLabel(sizeLabel, near: selection) }
        } else if let highlight = windowHighlight?.intersection(bounds), highlight.width > 1, highlight.height > 1 {
            punch(highlight)
            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect: highlight)
            border.lineWidth = 3
            border.stroke()
        }

        if showsHint, selectionRect == nil {
            drawHint()
        }
    }

    private func drawBackground() {
        guard let image = backgroundImage, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: bounds)
        ctx.restoreGState()
    }

    /// 选区内重画快照，去掉暗色。不用全透明，避免点击穿透。
    private func punch(_ rect: NSRect) {
        guard let image = backgroundImage, let ctx = NSGraphicsContext.current?.cgContext else {
            NSColor(white: 1, alpha: 0.01).setFill()
            rect.fill()
            return
        }
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        let flipped = CGRect(
            x: rect.origin.x,
            y: bounds.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
        ctx.clip(to: flipped)
        ctx.draw(image, in: bounds)
        ctx.restoreGState()
    }

    /// 蓝、白、黑三层边框加角点，浅色和深色画面上都能看清选区。
    private func drawManualSelectionBorder(_ rect: NSRect) {
        NSColor.black.withAlphaComponent(0.9).setStroke()
        let outer = NSBezierPath(rect: rect.insetBy(dx: -2, dy: -2))
        outer.lineWidth = 2
        outer.stroke()

        NSColor.systemBlue.setStroke()
        let main = NSBezierPath(rect: rect)
        main.lineWidth = 3
        main.stroke()

        NSColor.white.setStroke()
        let inner = NSBezierPath(rect: rect.insetBy(dx: 2, dy: 2))
        inner.lineWidth = 1.5
        inner.stroke()

        let handle: CGFloat = 10
        let corners = [
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.midX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.midY),
            NSPoint(x: rect.maxX, y: rect.midY),
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.midX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY),
        ]
        for point in corners {
            let box = NSRect(x: point.x - handle / 2, y: point.y - handle / 2, width: handle, height: handle)
            NSColor.white.setFill()
            NSBezierPath(rect: box).fill()
            NSColor.systemBlue.setStroke()
            let stroke = NSBezierPath(rect: box)
            stroke.lineWidth = 1.5
            stroke.stroke()
        }
    }

    private func drawLabel(_ text: String, near rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        var origin = NSPoint(x: rect.minX, y: rect.minY - size.height - 8)
        if origin.y < 4 { origin.y = rect.maxY + 6 }
        let background = NSRect(
            x: origin.x - 6,
            y: origin.y - 3,
            width: size.width + 12,
            height: size.height + 6
        )
        NSColor(white: 0, alpha: 0.72).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    private func drawHint() {
        let text = "Drag to select   ·   Click a window   ·   Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: 36)
        let background = NSRect(
            x: origin.x - 10,
            y: origin.y - 6,
            width: size.width + 20,
            height: size.height + 12
        )
        NSColor(white: 0, alpha: 0.72).setFill()
        NSBezierPath(roundedRect: background, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }
}
