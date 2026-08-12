import AppKit

/// A panel that never takes key/main focus — so the app being dictated into keeps it.
final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The single, adaptive Speak pill — it replaces both the old floating dock and the
/// recording HUD.
///
/// States:
///   - collapsed:     a small indigo mic orb (shown only when idle-visible is on)
///   - expanded:      hover slides out History / Mic / Settings
///   - recording:     orb turns red, a live waveform morphs in
///   - transcribing:  "Transcribing…" with an animated ellipsis
///   - success:       brief "Inserted", then collapse/hide
///
/// Non-activating (never steals focus) and draggable; position + idle-visibility
/// persist. When idle-visibility is off, the pill still appears while dictating.
final class SpeakPill: NSObject, NSWindowDelegate {

    struct Callbacks {
        let toggleRecord: () -> Void
        let openHistory: (NSView) -> Void
        let openSettings: (NSView) -> Void
        let openMicMenu: (NSView) -> Void
        let level: () -> Float
    }

    enum Mode { case collapsed, expanded, recording, transcribing, success }

    private var panel: NonActivatingPanel?
    private var content: PillContentView?
    private var callbacks: Callbacks?
    private var levelTimer: Timer?
    private var ellipsisTimer: Timer?

    private let height: CGFloat = 46
    private let originKey = "speak.pill.origin"
    private let visibleKey = "speak.pill.idleVisible"
    private var previewing = false
    private var pinnedExpanded = false

    private(set) var mode: Mode = .collapsed

    var idleVisible: Bool { UserDefaults.standard.bool(forKey: visibleKey) }

    func configure(_ callbacks: Callbacks) { self.callbacks = callbacks }

    // MARK: - Idle visibility (menu toggle)

    func applyIdleVisibilityFromDefaults() {
        if idleVisible { setMode(.collapsed, show: true) }
    }

    func toggleIdleVisible() {
        let newValue = !idleVisible
        UserDefaults.standard.set(newValue, forKey: visibleKey)
        if newValue {
            setMode(.collapsed, show: true)
        } else if mode == .collapsed || mode == .expanded {
            hide()
        }
    }

    // MARK: - Dictation states

    func showRecording() {
        setMode(.recording, show: true)
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) {
            [weak self] _ in
            guard let self else { return }
            let level = self.previewing ? Float.random(in: 0.05...1.0) : (self.callbacks?.level() ?? 0)
            self.content?.pushLevel(level)
        }
    }

    /// Cycle through the states for a visual preview (no real recording).
    func preview() {
        previewing = true
        showRecording()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.showTranscribing() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.previewing = false
            self?.showSuccessThenHide()
        }
    }

    func showTranscribing() {
        stopLevelTimer()
        setMode(.transcribing, show: true)
        startEllipsis()
    }

    func showSuccessThenHide() {
        stopLevelTimer()
        stopEllipsis()
        setMode(.success, show: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            if self.idleVisible {
                self.setMode(.collapsed, show: true)
            } else {
                self.hide()
            }
        }
    }

    func returnToIdle() {
        stopLevelTimer()
        stopEllipsis()
        if idleVisible {
            setMode(.collapsed, show: true)
        } else {
            hide()
        }
    }

    // MARK: - Hover (from the content view)

    fileprivate func hoverChanged(inside: Bool) {
        // While the history panel is open we hold the pill expanded, so moving the
        // mouse off the pill (up into the panel) must not collapse it.
        guard !pinnedExpanded else { return }
        guard mode == .collapsed || mode == .expanded else { return }
        setMode(inside ? .expanded : .collapsed, show: true)
    }

    /// Keep the pill expanded regardless of hover (used while the history panel is
    /// open). Unpinning collapses/hides it as appropriate.
    func setExpandedPinned(_ pinned: Bool) {
        pinnedExpanded = pinned
        guard mode == .collapsed || mode == .expanded else { return }
        if pinned {
            setMode(.expanded, show: true)
        } else if idleVisible {
            setMode(.collapsed, show: true)
        } else {
            hide()
        }
    }

    // MARK: - Core

    private func setMode(_ newMode: Mode, show: Bool) {
        mode = newMode
        ensurePanel()
        guard let panel, let content else { return }

        content.apply(newMode)

        // Animate the panel width to the mode's target; keep the left/bottom origin.
        let width = content.targetWidth(for: newMode, height: height)
        let origin = panel.frame.origin
        let target = NSRect(x: origin.x, y: origin.y, width: width, height: height)

        if show && !panel.isVisible {
            panel.setFrame(target, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                panel.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.26
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.85, 0.25, 1)
                panel.animator().setFrame(target, display: true)
            }
        }
    }

    private func hide() {
        stopLevelTimer()
        stopEllipsis()
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = 0.16
                panel.animator().alphaValue = 0
            },
            completionHandler: { [weak panel] in panel?.orderOut(nil) })
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let view = PillContentView(height: height)
        view.owner = self
        view.callbacks = callbacks

        let p = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: height, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.delegate = self
        p.contentView = view

        panel = p
        content = view
        positionInitially(p)
    }

    private func positionInitially(_ panel: NSPanel) {
        if let saved = UserDefaults.standard.dictionary(forKey: originKey),
            let x = saved["x"] as? Double, let y = saved["y"] as? Double
        {
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - height / 2, y: frame.minY + 28))
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        UserDefaults.standard.set(
            ["x": panel.frame.origin.x, "y": panel.frame.origin.y], forKey: originKey)
    }

    // MARK: - Timers

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func startEllipsis() {
        var step = 0
        ellipsisTimer?.invalidate()
        ellipsisTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) {
            [weak self] _ in
            step = (step + 1) % 4
            self?.content?.setStatus("Transcribing" + String(repeating: ".", count: step))
        }
    }

    private func stopEllipsis() {
        ellipsisTimer?.invalidate()
        ellipsisTimer = nil
    }
}

// MARK: - Content view

private let pillColor = NSColor(calibratedRed: 0.098, green: 0.098, blue: 0.110, alpha: 1)
private let accentIndigo = NSColor(calibratedRed: 0.384, green: 0.341, blue: 0.902, alpha: 1)
private let recordRed = NSColor(calibratedRed: 0.886, green: 0.282, blue: 0.239, alpha: 1)
private let successGreen = NSColor(calibratedRed: 0.157, green: 0.722, blue: 0.373, alpha: 1)

private final class PillContentView: NSView {
    weak var owner: SpeakPill?
    var callbacks: SpeakPill.Callbacks?

    private let orb = NSButton()
    private let history = NSButton()
    private let mic = NSButton()
    private let settings = NSButton()
    private let wave = WaveformView()
    private let label = NSTextField(labelWithString: "")

    private let h: CGFloat
    private let pad: CGFloat = 5
    private let orbD: CGFloat
    private let ctrlD: CGFloat = 28
    private var tracking: NSTrackingArea?
    private var currentMode: SpeakPill.Mode = .collapsed

    init(height: CGFloat) {
        self.h = height
        self.orbD = height - 8
        super.init(frame: NSRect(x: 0, y: 0, width: height, height: height))
        wantsLayer = true
        layer?.backgroundColor = pillColor.cgColor
        layer?.cornerRadius = height / 2
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        layer?.masksToBounds = true

        configureButton(orb, symbol: "mic.fill", diameter: orbD, background: accentIndigo,
            action: #selector(orbTapped))
        for (button, symbol, action) in [
            (history, "clock", #selector(historyTapped)),
            (mic, "waveform", #selector(micTapped)),
            (settings, "gearshape", #selector(settingsTapped)),
        ] {
            configureButton(button, symbol: symbol, diameter: ctrlD,
                background: NSColor(calibratedWhite: 1, alpha: 0.10), action: action)
            addSubview(button)
        }
        addSubview(orb)

        wave.isHidden = true
        addSubview(wave)

        label.font = .systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = .white
        label.isHidden = true
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    private func configureButton(
        _ button: NSButton, symbol: String, diameter: CGFloat, background: NSColor, action: Selector
    ) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.backgroundColor = background.cgColor
        button.layer?.cornerRadius = diameter / 2
        button.target = self
        button.action = action
        setSymbol(button, symbol, pointSize: diameter * 0.42)
    }

    private func setSymbol(_ button: NSButton, _ name: String, pointSize: CGFloat) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    // MARK: layout

    func targetWidth(for mode: SpeakPill.Mode, height: CGFloat) -> CGFloat {
        let orbEnd = pad + orbD + 8
        switch mode {
        case .collapsed: return pad + orbD + pad
        case .expanded: return orbEnd + (ctrlD * 3 + 6 * 2) + pad
        case .recording: return orbEnd + 104 + 8
        case .transcribing, .success: return orbEnd + 118 + 10
        }
    }

    func apply(_ mode: SpeakPill.Mode) {
        currentMode = mode
        let idleish = (mode == .collapsed || mode == .expanded)
        [history, mic, settings].forEach { $0.isHidden = (mode != .expanded) }
        wave.isHidden = (mode != .recording)
        label.isHidden = !(mode == .transcribing || mode == .success)

        switch mode {
        case .recording:
            orb.layer?.backgroundColor = recordRed.cgColor
            setSymbol(orb, "stop.fill", pointSize: orbD * 0.42)
            wave.start()
        case .success:
            orb.layer?.backgroundColor = successGreen.cgColor
            setSymbol(orb, "checkmark", pointSize: orbD * 0.42)
            label.stringValue = "Inserted"
        case .transcribing:
            orb.layer?.backgroundColor = accentIndigo.cgColor
            setSymbol(orb, "waveform", pointSize: orbD * 0.42)
            label.stringValue = "Transcribing…"
        default:
            orb.layer?.backgroundColor = accentIndigo.cgColor
            setSymbol(orb, "mic.fill", pointSize: orbD * 0.42)
            wave.stop()
        }
        _ = idleish
        needsLayout = true
        layout()
    }

    func setStatus(_ text: String) { label.stringValue = text }
    func pushLevel(_ level: Float) { wave.push(level) }

    override func layout() {
        super.layout()
        orb.frame = NSRect(x: pad, y: (h - orbD) / 2, width: orbD, height: orbD)
        let contentX = pad + orbD + 8
        let cy = (h - ctrlD) / 2
        history.frame = NSRect(x: contentX, y: cy, width: ctrlD, height: ctrlD)
        mic.frame = NSRect(x: contentX + ctrlD + 6, y: cy, width: ctrlD, height: ctrlD)
        settings.frame = NSRect(x: contentX + (ctrlD + 6) * 2, y: cy, width: ctrlD, height: ctrlD)
        wave.frame = NSRect(x: contentX, y: 0, width: 104, height: h)
        label.frame = NSRect(x: contentX, y: (h - 18) / 2, width: 120, height: 18)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { owner?.hoverChanged(inside: true) }
    override func mouseExited(with event: NSEvent) { owner?.hoverChanged(inside: false) }

    @objc private func orbTapped() { callbacks?.toggleRecord() }
    @objc private func historyTapped() { callbacks?.openHistory(history) }
    @objc private func micTapped() { callbacks?.openMicMenu(mic) }
    @objc private func settingsTapped() { callbacks?.openSettings(settings) }
}

/// A centered, mirrored bar waveform driven by live mic levels.
final class WaveformView: NSView {
    private let barCount = 16
    private var levels: [CGFloat]
    private var running = false

    override init(frame frameRect: NSRect) {
        levels = Array(repeating: 0, count: barCount)
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    func start() {
        running = true
        levels = Array(repeating: 0, count: barCount)
        needsDisplay = true
    }

    func stop() {
        running = false
        needsDisplay = true
    }

    func push(_ level: Float) {
        levels.removeFirst()
        levels.append(CGFloat(max(0, min(1, level))))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard running else { return }
        let gap: CGFloat = 3
        let barW = (bounds.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
        let midY = bounds.height / 2
        let maxH = bounds.height * 0.6
        for (i, level) in levels.enumerated() {
            let recency = CGFloat(i) / CGFloat(barCount - 1)
            let alpha = 0.4 + 0.55 * recency
            let barHeight = max(3, level * maxH)
            let x = CGFloat(i) * (barW + gap)
            let rect = NSRect(x: x, y: midY - barHeight / 2, width: barW, height: barHeight)
            NSColor.white.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: barW / 2, yRadius: barW / 2).fill()
        }
    }
}
