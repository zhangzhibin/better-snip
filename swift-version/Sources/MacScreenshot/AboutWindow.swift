import Cocoa

/// 启动时短暂显示，或从菜单 About 打开。不激活应用，避免每次启动都出现 Dock 图标。
final class AboutWindow: NSPanel {
    private let backdrop = AboutBackdrop()
    private let closeButton = NSButton()
    private var dismissItem: DispatchWorkItem?
    private var autoDismiss = false
    private var presentationID = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 156),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.11, alpha: 1).cgColor
        backdrop.layer?.cornerRadius = 16
        backdrop.layer?.masksToBounds = true
        backdrop.onMouseDown = { [weak self] in
            guard let self, self.autoDismiss else { return }
            self.dismiss()
        }

        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        icon.size = NSSize(width: 88, height: 88)
        let iconView = NSImageView(image: icon)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: "Simple Snip")
        nameLabel.font = .systemFont(ofSize: 26, weight: .medium)
        nameLabel.textColor = .white

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.font = .systemFont(ofSize: 13)
        versionLabel.textColor = NSColor.white.withAlphaComponent(0.62)

        let textStack = NSStackView(views: [nameLabel, versionLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        let row = NSStackView(views: [iconView, textStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 18
        row.translatesAutoresizingMaskIntoConstraints = false

        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        backdrop.addSubview(row)
        backdrop.addSubview(closeButton)
        contentView = backdrop

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 88),
            iconView.heightAnchor.constraint(equalToConstant: 88),
            row.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: 28),
            row.trailingAnchor.constraint(lessThanOrEqualTo: backdrop.trailingAnchor, constant: -28),
            row.centerYAnchor.constraint(equalTo: backdrop.centerYAnchor),
            closeButton.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -12),
        ])
    }

    /// autoDismiss 为 true 时约 2 秒后淡出。About 打开时保持，直到关闭。
    func present(autoDismiss: Bool) {
        presentationID += 1
        let id = presentationID
        self.autoDismiss = autoDismiss
        closeButton.isHidden = autoDismiss
        dismissItem?.cancel()
        alphaValue = 0
        center()
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            animator().alphaValue = 1
        }
        guard autoDismiss else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.presentationID == id else { return }
            self.dismiss()
        }
        dismissItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func dismiss() {
        guard isVisible else { return }
        let id = presentationID
        dismissItem?.cancel()
        dismissItem = nil
        autoDismiss = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.presentationID == id else { return }
            self.orderOut(nil)
        })
    }

    @objc private func closeTapped() {
        dismiss()
    }
}

private final class AboutBackdrop: NSView {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }
}
