import AppKit

/// Shown when dictation found no text field to insert into.
///
/// The transcript is auto-copied to the clipboard immediately (so it's never lost),
/// and this toast surfaces it with a "Copy" button and the text preview. Unlike the
/// dictation pill this toast IS interactive (the button must be clickable), but it
/// still uses a non-activating panel so it doesn't steal focus.
final class CopyToast: NSObject {
    private var panel: NonActivatingPanel?
    private var dismissTimer: Timer?
    private var text: String = ""

    private let width: CGFloat = 340
    private let height: CGFloat = 92
    private var titleText = "Couldn’t insert — copied to clipboard"

    func show(_ text: String, title: String = "Couldn’t insert — copied to clipboard") {
        self.text = text
        self.titleText = title
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        build()
        guard let panel else { return }
        position(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }

        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) {
            [weak self] _ in self?.hide()
        }
    }

    @objc private func copyTapped() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        hide()
    }

    @objc private func hide() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = 0.16
                panel.animator().alphaValue = 0
            },
            completionHandler: { [weak self] in
                self?.panel?.orderOut(nil)
                self?.panel = nil
            })
    }

    private func build() {
        let p = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.wantsLayer = true
        content.layer?.backgroundColor =
            NSColor(calibratedRed: 0.106, green: 0.106, blue: 0.122, alpha: 1).cgColor
        content.layer?.cornerRadius = 14
        content.layer?.borderWidth = 0.5
        content.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        let title = NSTextField(labelWithString: titleText)
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.textColor = NSColor.white.withAlphaComponent(0.6)
        title.frame = NSRect(x: 16, y: height - 30, width: width - 32, height: 16)
        content.addSubview(title)

        let preview = NSTextField(labelWithString: text)
        preview.font = .systemFont(ofSize: 13)
        preview.textColor = .white
        preview.lineBreakMode = .byTruncatingTail
        preview.maximumNumberOfLines = 2
        preview.frame = NSRect(x: 16, y: 30, width: width - 100, height: 34)
        content.addSubview(preview)

        let copy = NSButton(title: "Copy", target: self, action: #selector(copyTapped))
        copy.bezelStyle = .rounded
        copy.frame = NSRect(x: width - 78, y: 14, width: 62, height: 26)
        copy.keyEquivalent = ""
        content.addSubview(copy)

        p.contentView = content
        panel = p
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrame(
            NSRect(x: visible.midX - width / 2, y: visible.minY + 120, width: width, height: height),
            display: true)
    }
}
