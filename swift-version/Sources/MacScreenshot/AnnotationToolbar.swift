import Cocoa

protocol AnnotationToolbarDelegate: AnyObject {
    func toolbarDidSelectTool(_ tool: AnnotationTool)
    func toolbarDidSelectColor(_ color: NSColor)
    func toolbarDidSelectLineWidth(_ width: CGFloat)
    func toolbarDidSelectFontName(_ name: String)
    func toolbarDidSelectFontSize(_ size: CGFloat)
    func toolbarDidSelectDashPattern(_ pattern: [CGFloat])
    func toolbarDidSelectCropAspectRatio(_ ratio: CropAspectRatio?)
    func toolbarDidToggleBold()
    func toolbarDidToggleItalic()
    func toolbarDidUndo()
    func toolbarDidDone()
}

class AnnotationToolbar: NSView {
    weak var delegate: AnnotationToolbarDelegate?

    private(set) var currentTool: AnnotationTool = .arrow
    private(set) var currentColor: NSColor = .systemRed
    private(set) var currentLineWidth: CGFloat = 2.5
    private(set) var currentFontName: String = "system"
    private(set) var currentFontSize: CGFloat = 16

    private var toolButtons: [NSButton] = []
    private var colorPopup: NSPopUpButton!
    private var widthPopup: NSPopUpButton!
    private var dashPopup: NSPopUpButton!
    private var textOptionsStack: NSStackView!
    private var cropRatioPopup: NSPopUpButton!
    private var mainStack: NSStackView!

    override var isFlipped: Bool { true }

    static let toolbarHeight: CGFloat = 44

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        mainStack = NSStackView()
        mainStack.orientation = .horizontal
        mainStack.spacing = 6
        mainStack.alignment = .centerY
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            mainStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // 工具按钮
        let tools: [(AnnotationTool, String, String)] = [
            (.arrow, "arrow.up.right", "Arrow"),
            (.rect, "rectangle", "Rect"),
            (.ellipse, "circle", "Ellipse"),
            (.line, "line.diagonal", "Line"),
            (.freehand, "pencil.tip", "Freehand"),
            (.text, "textformat", "Text"),
            (.mosaic, "square.grid.3x3.fill", "Mosaic"),
            (.crop, "crop", "Crop"),
        ]
        for (tool, symbol, title) in tools {
            let btn = makeToolButton(symbol: symbol, fallback: title, tag: tool.hashValue)
            btn.action = #selector(toolTapped(_:))
            btn.target = self
            toolButtons.append(btn)
            mainStack.addArrangedSubview(btn)
        }

        mainStack.addArrangedSubview(makeSeparator())

        // 颜色下拉列表
        colorPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        colorPopup.controlSize = .small
        let colorItems: [(NSColor, String)] = [
            (.systemRed, "Red"), (.systemBlue, "Blue"), (.systemGreen, "Green"),
            (.systemYellow, "Yellow"), (.black, "Black"), (.white, "White"),
        ]
        for (color, name) in colorItems {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.image = makeColorSwatch(color: color, size: 14)
            colorPopup.menu?.addItem(item)
        }
        colorPopup.target = self
        colorPopup.action = #selector(colorChanged(_:))
        mainStack.addArrangedSubview(colorPopup)

        mainStack.addArrangedSubview(makeSeparator())

        // 线宽下拉列表
        widthPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        widthPopup.controlSize = .small
        let widthItems: [(CGFloat, String)] = [(1, "Thin"), (2.5, "Medium"), (5, "Thick")]
        for (width, label) in widthItems {
            let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            item.image = makeLineIcon(width: width, canvasSize: NSSize(width: 28, height: 16))
            widthPopup.menu?.addItem(item)
        }
        widthPopup.selectItem(at: 1)
        widthPopup.target = self
        widthPopup.action = #selector(widthChanged(_:))
        mainStack.addArrangedSubview(widthPopup)

        // 虚线样式下拉列表
        dashPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        dashPopup.controlSize = .small
        let dashStyles: [([CGFloat], String)] = [
            ([], "Solid"),
            ([8, 4], "Dashed"),
            ([2, 4], "Dotted"),
            ([8, 4, 2, 4], "Dash-Dot"),
        ]
        for (pattern, label) in dashStyles {
            let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            item.image = makeDashIcon(pattern: pattern, lineWidth: 2, canvasSize: NSSize(width: 36, height: 16))
            dashPopup.menu?.addItem(item)
        }
        dashPopup.target = self
        dashPopup.action = #selector(dashChanged(_:))
        mainStack.addArrangedSubview(dashPopup)

        mainStack.addArrangedSubview(makeSeparator())

        // 文字选项（仅 text 工具时显示）
        textOptionsStack = NSStackView()
        textOptionsStack.orientation = .horizontal
        textOptionsStack.spacing = 4

        let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        fontPopup.addItems(withTitles: ["System", "Mono", "Serif"])
        fontPopup.controlSize = .small
        fontPopup.target = self
        fontPopup.action = #selector(fontChanged(_:))
        fontPopup.tag = 100
        textOptionsStack.addArrangedSubview(fontPopup)

        let sizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        sizePopup.addItems(withTitles: ["12", "16", "24", "36"])
        sizePopup.selectItem(at: 1)
        sizePopup.controlSize = .small
        sizePopup.target = self
        sizePopup.action = #selector(sizeChanged(_:))
        sizePopup.tag = 101
        textOptionsStack.addArrangedSubview(sizePopup)

        let boldBtn = NSButton(title: "B", target: self, action: #selector(boldTapped))
        boldBtn.bezelStyle = .recessed
        boldBtn.setButtonType(.onOff)
        boldBtn.controlSize = .small
        let boldFont = NSFont.boldSystemFont(ofSize: 12)
        boldBtn.attributedTitle = NSAttributedString(string: "B", attributes: [.font: boldFont])
        textOptionsStack.addArrangedSubview(boldBtn)

        let italicBtn = NSButton(title: "I", target: self, action: #selector(italicTapped))
        italicBtn.bezelStyle = .recessed
        italicBtn.setButtonType(.onOff)
        italicBtn.controlSize = .small
        let italicFont = NSFont(descriptor: NSFont.systemFont(ofSize: 12).fontDescriptor.withSymbolicTraits(.italic), size: 12) ?? .systemFont(ofSize: 12)
        italicBtn.attributedTitle = NSAttributedString(string: "I", attributes: [.font: italicFont])
        textOptionsStack.addArrangedSubview(italicBtn)

        textOptionsStack.isHidden = true
        mainStack.addArrangedSubview(textOptionsStack)

        // 裁剪比例（仅 crop 工具时显示）
        cropRatioPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        cropRatioPopup.controlSize = .small
        for ratio in CropAspectRatio.allCases {
            cropRatioPopup.menu?.addItem(withTitle: ratio.displayName, action: nil, keyEquivalent: "")
        }
        cropRatioPopup.target = self
        cropRatioPopup.action = #selector(cropRatioChanged(_:))
        cropRatioPopup.isHidden = true
        mainStack.addArrangedSubview(cropRatioPopup)

        // 弹性空间
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        mainStack.addArrangedSubview(spacer)

        // 关闭（丢弃）+ 保存
        let closeBtn = makeIconButton(symbol: "xmark.circle", fallback: "✕", tooltip: "Discard & Close")
        closeBtn.target = self
        closeBtn.action = #selector(undoTapped)
        mainStack.addArrangedSubview(closeBtn)

        let saveBtn = makeIconButton(symbol: "checkmark.circle", fallback: "Save", tooltip: "Save (Return)")
        saveBtn.title = "Save"
        saveBtn.imagePosition = .imageLeading
        saveBtn.bezelStyle = .rounded
        saveBtn.setButtonType(.momentaryPushIn)
        saveBtn.controlSize = .regular
        // 回车键等价使它成为窗口的首选按钮，使用强调色。
        saveBtn.keyEquivalent = "\r"
        saveBtn.target = self
        saveBtn.action = #selector(doneTapped)
        mainStack.addArrangedSubview(saveBtn)

        updateToolSelection()
    }

    /// 按钮按固有宽度排开所需的窗口内容宽度。弹性空白不计入。
    var minimumContentWidth: CGFloat {
        var width: CGFloat = 16
        var count = 0
        for view in mainStack.arrangedSubviews where !view.isHidden {
            let itemWidth = view.fittingSize.width
            guard itemWidth.isFinite, itemWidth >= 1, itemWidth < 8_000 else { continue }
            width += itemWidth
            count += 1
        }
        if count > 1 {
            width += mainStack.spacing * CGFloat(count - 1)
        }
        return ceil(width)
    }

    // MARK: - Actions

    @objc private func toolTapped(_ sender: NSButton) {
        let tools = AnnotationTool.allCases
        if let idx = toolButtons.firstIndex(of: sender), idx < tools.count {
            currentTool = tools[idx]
            updateToolSelection()
            textOptionsStack.isHidden = (currentTool != .text)
            cropRatioPopup.isHidden = (currentTool != .crop)
            delegate?.toolbarDidSelectTool(currentTool)
        }
    }

    @objc private func cropRatioChanged(_ sender: NSPopUpButton) {
        let ratios = CropAspectRatio.allCases
        let idx = sender.indexOfSelectedItem
        delegate?.toolbarDidSelectCropAspectRatio(idx < ratios.count ? ratios[idx] : nil)
    }

    @objc private func colorChanged(_ sender: NSPopUpButton) {
        let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow, .black, .white]
        let idx = sender.indexOfSelectedItem
        if idx < colors.count {
            currentColor = colors[idx]
            delegate?.toolbarDidSelectColor(currentColor)
        }
    }

    @objc private func widthChanged(_ sender: NSPopUpButton) {
        let widths: [CGFloat] = [1, 2.5, 5]
        let idx = sender.indexOfSelectedItem
        if idx < widths.count {
            currentLineWidth = widths[idx]
            delegate?.toolbarDidSelectLineWidth(currentLineWidth)
        }
    }

    @objc private func dashChanged(_ sender: NSPopUpButton) {
        let patterns: [[CGFloat]] = [[], [8, 4], [2, 4], [8, 4, 2, 4]]
        let idx = sender.indexOfSelectedItem
        if idx < patterns.count {
            delegate?.toolbarDidSelectDashPattern(patterns[idx])
        }
    }

    @objc private func fontChanged(_ sender: NSPopUpButton) {
        let names = ["system", "mono", "serif"]
        let idx = sender.indexOfSelectedItem
        if idx < names.count {
            currentFontName = names[idx]
            delegate?.toolbarDidSelectFontName(currentFontName)
        }
    }

    @objc private func sizeChanged(_ sender: NSPopUpButton) {
        let sizes: [CGFloat] = [12, 16, 24, 36]
        let idx = sender.indexOfSelectedItem
        if idx < sizes.count {
            currentFontSize = sizes[idx]
            delegate?.toolbarDidSelectFontSize(currentFontSize)
        }
    }

    @objc private func boldTapped() { delegate?.toolbarDidToggleBold() }
    @objc private func italicTapped() { delegate?.toolbarDidToggleItalic() }
    @objc private func undoTapped() { delegate?.toolbarDidUndo() }
    @objc private func doneTapped() { delegate?.toolbarDidDone() }

    // MARK: - UI Updates

    private func updateToolSelection() {
        let tools = AnnotationTool.allCases
        for (i, btn) in toolButtons.enumerated() {
            btn.state = (i < tools.count && tools[i] == currentTool) ? .on : .off
        }
    }

    // MARK: - Helpers

    private func makeToolButton(symbol: String, fallback: String, tag: Int) -> NSButton {
        let btn: NSButton
        if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: symbol, accessibilityDescription: fallback) {
            btn = NSButton(image: img, target: nil, action: nil)
        } else {
            btn = NSButton(title: fallback, target: nil, action: nil)
        }
        btn.bezelStyle = .recessed
        btn.setButtonType(.onOff)
        btn.controlSize = .small
        btn.tag = tag
        btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        return btn
    }

    private func makeIconButton(symbol: String, fallback: String, tooltip: String) -> NSButton {
        let btn: NSButton
        if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) {
            btn = NSButton(image: img, target: nil, action: nil)
        } else {
            btn = NSButton(title: fallback, target: nil, action: nil)
        }
        btn.bezelStyle = .recessed
        btn.controlSize = .small
        btn.toolTip = tooltip
        btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        return btn
    }

    /// 生成颜色色块图标
    private func makeColorSwatch(color: NSColor, size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        color.setFill()
        let path = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: size - 2, height: size - 2))
        path.fill()
        if color == .white || color == .systemYellow {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }
        img.unlockFocus()
        return img
    }

    /// 生成线宽示意图标
    private func makeLineIcon(width: CGFloat, canvasSize: NSSize) -> NSImage {
        let img = NSImage(size: canvasSize)
        img.lockFocus()
        NSColor.labelColor.setStroke()
        let path = NSBezierPath()
        let y = canvasSize.height / 2
        path.move(to: NSPoint(x: 2, y: y))
        path.line(to: NSPoint(x: canvasSize.width - 2, y: y))
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()
        img.unlockFocus()
        return img
    }

    /// 生成虚线样式图标
    private func makeDashIcon(pattern: [CGFloat], lineWidth: CGFloat, canvasSize: NSSize) -> NSImage {
        let img = NSImage(size: canvasSize)
        img.lockFocus()
        NSColor.labelColor.setStroke()
        let path = NSBezierPath()
        let y = canvasSize.height / 2
        path.move(to: NSPoint(x: 2, y: y))
        path.line(to: NSPoint(x: canvasSize.width - 2, y: y))
        path.lineWidth = lineWidth
        path.lineCapStyle = .butt
        if !pattern.isEmpty {
            path.setLineDash(pattern, count: pattern.count, phase: 0)
        }
        path.stroke()
        img.unlockFocus()
        return img
    }

    /// 外部切换工具（如 Esc 切回箭头）
    func selectTool(_ tool: AnnotationTool) {
        currentTool = tool
        updateToolSelection()
        textOptionsStack.isHidden = (currentTool != .text)
        cropRatioPopup.isHidden = (currentTool != .crop)
        delegate?.toolbarDidSelectTool(currentTool)
    }

    private func makeSeparator() -> NSView {
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
        sep.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return sep
    }
}
