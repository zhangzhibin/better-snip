import Cocoa

/// 快捷键、保存位置、默认写入剪贴板还是文件。
final class PreferencesWindow: NSWindow, NSWindowDelegate {
    var onSuspendShortcut: ((Bool) -> Void)?
    var onShortcutChanged: (() -> Void)?
    var onClose: (() -> Void)?

    private let recorder = ShortcutRecorder()
    private let destinationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let pathLabel = NSTextField(labelWithString: "")

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 188),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "Preferences"
        isReleasedWhenClosed = false
        delegate = self

        let shortcutLabel = NSTextField(labelWithString: "Shortcut")
        let destinationLabel = NSTextField(labelWithString: "Save to")
        let folderLabel = NSTextField(labelWithString: "Folder")
        for label in [shortcutLabel, destinationLabel, folderLabel] {
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

        let hint = NSTextField(wrappingLabelWithString: "Hold Option to swap Clipboard and File. Clipboard and File always writes both. Delete in the shortcut field turns the shortcut off.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let grid = NSGridView(views: [
            [shortcutLabel, recorder],
            [destinationLabel, destinationPopup],
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
        ])
    }

    func windowWillClose(_ notification: Notification) {
        onSuspendShortcut?(false)
        onClose?()
    }

    @objc private func destinationChanged(_ sender: NSPopUpButton) {
        let values: [SaveDestination] = [.clipboard, .file, .both]
        let index = sender.indexOfSelectedItem
        AppPreferences.destination = index < values.count ? values[index] : .clipboard
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

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            onFocus?(true)
            needsDisplay = true
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            onFocus?(false)
            needsDisplay = true
        }
        return ok
    }

    override func keyDown(with event: NSEvent) {
        record(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        record(event)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let focused = window?.firstResponder === self
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
        (focused ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (focused ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = focused ? 2 : 1
        path.stroke()

        let text = focused ? "Type shortcut" : display
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    private func record(_ event: NSEvent) {
        if event.timestamp == lastTimestamp { return }
        lastTimestamp = event.timestamp

        if event.keyCode == 51 || event.keyCode == 117 {
            onReset?()
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        guard !modifiers.isEmpty else { return }
        guard let raw = event.charactersIgnoringModifiers?.lowercased(), raw.count == 1,
              let character = raw.first, character.isLetter || character.isNumber else { return }
        onChange?(event.keyCode, modifiers, String(character))
    }
}
