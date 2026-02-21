import Cocoa

protocol AnnotationToolbarDelegate: AnyObject {
    func toolbarDidSelectTool(_ tool: AnnotationTool)
    func toolbarDidSelectColor(_ color: NSColor)
    func toolbarDidSelectLineWidth(_ width: CGFloat)
    func toolbarDidSelectFontName(_ name: String)
    func toolbarDidSelectFontSize(_ size: CGFloat)
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
    private var colorButtons: [NSButton] = []
    private var widthButtons: [NSButton] = []
    private var textOptionsStack: NSStackView!

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

        let mainStack = NSStackView()
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
        ]
        for (tool, symbol, title) in tools {
            let btn = makeToolButton(symbol: symbol, fallback: title, tag: tool.hashValue)
            btn.action = #selector(toolTapped(_:))
            btn.target = self
            toolButtons.append(btn)
            mainStack.addArrangedSubview(btn)
        }

        mainStack.addArrangedSubview(makeSeparator())

        // 颜色
        let colors: [(NSColor, String)] = [
            (.systemRed, "Red"), (.systemBlue, "Blue"), (.systemGreen, "Green"),
            (.systemYellow, "Yellow"), (.black, "Black"), (.white, "White"),
        ]
        for (color, name) in colors {
            let btn = makeColorButton(color: color, name: name)
            btn.action = #selector(colorTapped(_:))
            btn.target = self
            colorButtons.append(btn)
            mainStack.addArrangedSubview(btn)
        }

        mainStack.addArrangedSubview(makeSeparator())

        // 线宽
        let widths: [(CGFloat, String)] = [(1, "Thin"), (2.5, "Med"), (5, "Thick")]
        for (i, (_, label)) in widths.enumerated() {
            let btn = NSButton(title: label, target: self, action: #selector(widthTapped(_:)))
            btn.bezelStyle = .recessed
            btn.setButtonType(.onOff)
            btn.tag = i
            btn.state = (i == 1) ? .on : .off
            btn.controlSize = .small
            btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
            widthButtons.append(btn)
            mainStack.addArrangedSubview(btn)
        }

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

        // 弹性空间
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        mainStack.addArrangedSubview(spacer)

        // Undo + Done
        let undoBtn = NSButton(title: "Undo", target: self, action: #selector(undoTapped))
        undoBtn.bezelStyle = .recessed
        undoBtn.controlSize = .small
        mainStack.addArrangedSubview(undoBtn)

        let doneBtn = NSButton(title: "Done", target: self, action: #selector(doneTapped))
        doneBtn.bezelStyle = .rounded
        doneBtn.controlSize = .small
        doneBtn.keyEquivalent = "\r"
        mainStack.addArrangedSubview(doneBtn)

        updateToolSelection()
        updateColorSelection()
    }

    // MARK: - Actions

    @objc private func toolTapped(_ sender: NSButton) {
        let tools = AnnotationTool.allCases
        if let idx = toolButtons.firstIndex(of: sender), idx < tools.count {
            currentTool = tools[idx]
            updateToolSelection()
            textOptionsStack.isHidden = (currentTool != .text)
            delegate?.toolbarDidSelectTool(currentTool)
        }
    }

    @objc private func colorTapped(_ sender: NSButton) {
        let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow, .black, .white]
        if let idx = colorButtons.firstIndex(of: sender), idx < colors.count {
            currentColor = colors[idx]
            updateColorSelection()
            delegate?.toolbarDidSelectColor(currentColor)
        }
    }

    @objc private func widthTapped(_ sender: NSButton) {
        let widths: [CGFloat] = [1, 2.5, 5]
        for (i, btn) in widthButtons.enumerated() {
            btn.state = (btn == sender) ? .on : .off
            if btn == sender, i < widths.count { currentLineWidth = widths[i] }
        }
        delegate?.toolbarDidSelectLineWidth(currentLineWidth)
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

    private func updateColorSelection() {
        let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow, .black, .white]
        for (i, btn) in colorButtons.enumerated() {
            btn.layer?.borderWidth = (i < colors.count && colors[i] == currentColor) ? 2 : 0
            btn.layer?.borderColor = NSColor.controlAccentColor.cgColor
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

    private func makeColorButton(color: NSColor, name: String) -> NSButton {
        let btn = NSButton(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        btn.wantsLayer = true
        btn.layer?.backgroundColor = color.cgColor
        btn.layer?.cornerRadius = 10
        btn.layer?.masksToBounds = true
        btn.isBordered = false
        btn.title = ""
        btn.toolTip = name
        btn.widthAnchor.constraint(equalToConstant: 20).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return btn
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
