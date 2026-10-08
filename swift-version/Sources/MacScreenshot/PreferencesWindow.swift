import Cocoa

/// 快捷键、保存位置、默认写入剪贴板还是文件。
final class PreferencesWindow: NSWindow, NSWindowDelegate {
    var onSuspendShortcut: ((Bool) -> Void)?
    var onShortcutChanged: (() -> Void)?
    var onClose: (() -> Void)?

    private let recorder = ShortcutRecorder()
    private let destinationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let qualitySlider = NSSlider(value: 90, minValue: 1, maxValue: 100, target: nil, action: nil)
    private let qualityLabel = NSTextField(labelWithString: "90%")
    private let pathLabel = NSTextField(labelWithString: "")

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "Preferences"
        isReleasedWhenClosed = false
        delegate = self

        let shortcutLabel = NSTextField(labelWithString: "Shortcut")
        let destinationLabel = NSTextField(labelWithString: "Save to")
        let formatLabel = NSTextField(labelWithString: "Format")
        let qualityTitle = NSTextField(labelWithString: "Quality")
        let folderLabel = NSTextField(labelWithString: "Folder")
        for label in [shortcutLabel, destinationLabel, formatLabel, qualityTitle, folderLabel] {
            label.alignment = .right
            label.font = .systemFont(ofSize: 13)
        }

        recorder.onChange = { [weak self] keyCode, modifiers, character in
            AppPreferences.isHotkeyEnabled = true
            AppPreferences.hotkeyKeyCode = keyCode
            AppPreferences.hotkeyModifiers = modifiers
            AppPreferences.hotkeyCharacter = character
            self?.recorder.display = AppPreferences.shortcutDisplay()
            self?.onShortcutChanged?()
        }
        recorder.onReset = { [weak self] in
            AppPreferences.clearHotkey()
            self?.recorder.display = AppPreferences.shortcutDisplay()
            self?.onShortcutChanged?()
        }
        recorder.onFocus = { [weak self] focused in
            self?.onSuspendShortcut?(focused)
        }
        recorder.display = AppPreferences.shortcutDisplay()

        destinationPopup.addItems(withTitles: ["Clipboard", "File", "Clipboard and File"])
        destinationPopup.target = self
        destinationPopup.action = #selector(destinationChanged(_:))
        switch AppPreferences.destination {
        case .clipboard: destinationPopup.selectItem(at: 0)
        case .file: destinationPopup.selectItem(at: 1)
        case .both: destinationPopup.selectItem(at: 2)
        }

        formatPopup.addItems(withTitles: ["PNG", "Lossless PNG", "JPEG", "WebP"])
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged(_:))
        switch AppPreferences.imageFormat {
        case .png: formatPopup.selectItem(at: 0)
        case .losslessPng: formatPopup.selectItem(at: 1)
        case .jpeg: formatPopup.selectItem(at: 2)
        case .webp: formatPopup.selectItem(at: 3)
        }

        qualitySlider.minValue = 1
        qualitySlider.maxValue = 100
        qualitySlider.doubleValue = Double(AppPreferences.imageQuality)
        qualitySlider.isContinuous = true
        qualitySlider.target = self
        qualitySlider.action = #selector(qualityChanged(_:))
        qualityLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        qualityLabel.alignment = .right
        updateQualityControls()

        let qualityRow = NSStackView(views: [qualitySlider, qualityLabel])
        qualityRow.orientation = .horizontal
        qualityRow.alignment = .centerY
        qualitySlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        qualityLabel.setContentHuggingPriority(.required, for: .horizontal)

        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.textColor = .secondaryLabelColor
        updatePathLabel()

        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        chooseButton.bezelStyle = .rounded

        let folderRow = NSStackView(views: [pathLabel, chooseButton])
        folderRow.orientation = .horizontal
        folderRow.alignment = .centerY
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let hint = NSTextField(wrappingLabelWithString: "Hold Option to swap Clipboard and File. PNG merges similar colors automatically. Quality applies to JPEG and WebP. Clipboard stays lossless. Delete in the shortcut field turns the shortcut off.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let restoreButton = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        restoreButton.bezelStyle = .rounded
        restoreButton.translatesAutoresizingMaskIntoConstraints = false

        let grid = NSGridView(views: [
            [shortcutLabel, recorder],
            [destinationLabel, destinationPopup],
            [formatLabel, formatPopup],
            [qualityTitle, qualityRow],
            [folderLabel, folderRow],
        ])
        grid.columnSpacing = 12
        grid.rowSpacing = 12
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false
        hint.translatesAutoresizingMaskIntoConstraints = false

        guard let content = contentView else { return }
        content.addSubview(grid)
        content.addSubview(hint)
        content.addSubview(restoreButton)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            recorder.widthAnchor.constraint(equalToConstant: 180),
            recorder.heightAnchor.constraint(equalToConstant: 28),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            hint.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            hint.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
            restoreButton.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 16),
            restoreButton.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
        ])
    }

    func windowWillClose(_ notification: Notification) {
        onSuspendShortcut?(false)
        onClose?()
    }

    func refreshShortcutField() {
        recorder.display = AppPreferences.shortcutDisplay()
    }

    @objc private func destinationChanged(_ sender: NSPopUpButton) {
        let values: [SaveDestination] = [.clipboard, .file, .both]
        let index = sender.indexOfSelectedItem
        AppPreferences.destination = index < values.count ? values[index] : .clipboard
    }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        let values: [ImageFileFormat] = [.png, .losslessPng, .jpeg, .webp]
        let index = sender.indexOfSelectedItem
        AppPreferences.imageFormat = index < values.count ? values[index] : .png
        updateQualityControls()
    }

    @objc private func qualityChanged(_ sender: NSSlider) {
        AppPreferences.imageQuality = Int(sender.doubleValue.rounded())
        updateQualityControls()
    }

    private func updateQualityControls() {
        let format = AppPreferences.imageFormat
        qualitySlider.isEnabled = format.usesQuality
        if format.usesQuality {
            qualityLabel.stringValue = "\(AppPreferences.imageQuality)%"
            qualityLabel.textColor = .labelColor
        } else if format == .png {
            qualityLabel.stringValue = "Auto"
            qualityLabel.textColor = .secondaryLabelColor
        } else {
            qualityLabel.stringValue = "—"
            qualityLabel.textColor = .secondaryLabelColor
        }
    }

    @objc private func restoreDefaults() {
        AppPreferences.restoreDefaults()
        recorder.display = AppPreferences.shortcutDisplay()
        switch AppPreferences.destination {
        case .clipboard: destinationPopup.selectItem(at: 0)
        case .file: destinationPopup.selectItem(at: 1)
        case .both: destinationPopup.selectItem(at: 2)
        }
        switch AppPreferences.imageFormat {
        case .png: formatPopup.selectItem(at: 0)
        case .losslessPng: formatPopup.selectItem(at: 1)
        case .jpeg: formatPopup.selectItem(at: 2)
        case .webp: formatPopup.selectItem(at: 3)
        }
        qualitySlider.doubleValue = Double(AppPreferences.imageQuality)
        updateQualityControls()
        updatePathLabel()
        HotKeyCenter.shared.registerCurrent()
        onShortcutChanged?()
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = AppPreferences.saveDirectory
        panel.prompt = "Choose"
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            AppPreferences.saveDirectory = url
            self?.updatePathLabel()
        }
    }

    private func updatePathLabel() {
        pathLabel.stringValue = (AppPreferences.saveDirectory.path as NSString).abbreviatingWithTildeInPath
    }
}

private final class ShortcutRecorder: NSView {
    var display = "⌘⌥C" { didSet { needsDisplay = true } }
    var onChange: ((UInt16, NSEvent.ModifierFlags, String) -> Void)?
    var onReset: (() -> Void)?
    var onFocus: ((Bool) -> Void)?

    private var lastTimestamp: TimeInterval = -1
    /// 只有点进输入框才进入录制。窗口打开时系统可能把焦点丢进来，那种情况不进入录制。
    private var isRecording = false
    private var keyMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok, !isRecording {
            // 偏好设置刚打开时不要停在录制态，否则快捷键看起来是空的。
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isRecording else { return }
                self.window?.makeFirstResponder(nil)
            }
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            endRecording()
        }
        return ok
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        record(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else { return false }
        record(event)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text = isRecording ? "Type shortcut" : display
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        needsDisplay = true
        onFocus?(true)
        window?.makeFirstResponder(self)
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isRecording, self.window?.isKeyWindow == true else { return event }
                self.record(event)
                return nil
            }
        }
    }

    private func endRecording() {
        let wasRecording = isRecording
        isRecording = false
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if wasRecording {
            onFocus?(false)
        }
        needsDisplay = true
    }

    private func record(_ event: NSEvent) {
        if event.timestamp == lastTimestamp { return }
        lastTimestamp = event.timestamp

        if event.keyCode == 51 || event.keyCode == 117 {
            onReset?()
            finishRecording()
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        guard !modifiers.isEmpty else { return }
        guard let raw = event.charactersIgnoringModifiers?.lowercased(), raw.count == 1,
              let character = raw.first, character.isLetter || character.isNumber else { return }
        onChange?(event.keyCode, modifiers, String(character))
        finishRecording()
    }

    /// 延后结束，避免在按键监控的回调里拆掉监控本身。
    private func finishRecording() {
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(nil)
        }
    }
}
