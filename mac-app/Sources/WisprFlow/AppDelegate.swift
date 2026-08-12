import AVFoundation
import AppKit
import SwiftUI

/// Overall app state, reflected in the menu-bar icon.
enum DictationState {
    case idle
    case recording
    case processing

    var symbol: String {
        switch self {
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .processing: return "waveform"
        }
    }

    var tooltip: String {
        switch self {
        case .idle: return "Speak — hold Right Option to dictate"
        case .recording: return "Recording… release to transcribe"
        case .processing: return "Transcribing…"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let recorder = AudioRecorder()
    private let transcriber = TranscriptionClient()
    private let inserter = TextInserter()
    private let pill = SpeakPill()
    private let copyToast = CopyToast()
    private let history = HistoryStore()
    private let popover = NSPopover()
    private var contextMenu: NSMenu!
    private weak var dockMenuItem: NSMenuItem?
    // The app that was frontmost before the panel opened — the target for a
    // panel-triggered dictation (since opening the panel makes us frontmost).
    private var panelPreviousApp: NSRunningApplication?
    private var hotkey: HotkeyManager!

    // Menu item whose title flips between Start/Stop with the state.
    private weak var toggleItem: NSMenuItem?
    // Safety cap: auto-stop a recording that runs too long (e.g. a stuck toggle).
    private var maxDurationTimer: Timer?
    private let maxRecordingSeconds: TimeInterval = 120

    private var state: DictationState = .idle {
        didSet { DispatchQueue.main.async { self.refreshStatusIcon() } }
    }

    // The app that was frontmost when recording started — the paste target.
    private var targetAppName: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog(
            "Speak: launched (build v3). accessibility=\(Permissions.hasAccessibility(prompt: false)) "
                + "mic=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
        // Floating pill visible by default; an explicit toggle-off overrides this.
        UserDefaults.standard.register(defaults: ["speak.pill.idleVisible": true])
        setupStatusItem()
        setupPill()
        refreshStatusIcon()

        // Ask for microphone access up front.
        Permissions.requestMicrophone { granted in
            if !granted {
                DispatchQueue.main.async { self.showPermissionAlert(kind: .microphone) }
            }
        }

        // Push-to-talk: start on key down, stop on key up.
        hotkey = HotkeyManager(
            onPress: { [weak self] in self?.startDictation() },
            onRelease: { [weak self] in self?.stopDictation() }
        )

        if !Permissions.hasAccessibility(prompt: true) {
            // Accessibility is required both to observe the global hotkey and to
            // paste into other apps. The system prompt has been shown.
            showPermissionAlert(kind: .accessibility)
        }
        hotkey.start()
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Left-click → Speak panel (history); right-click → utility menu.
        if let button = statusItem.button {
            button.action = #selector(statusButtonClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        setupPopover()
        setupContextMenu()
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
        let actions = HistoryActions(
            copy: { [weak self] text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                _ = self
            },
            clear: { [weak self] in self?.history.clear() },
            quit: { NSApplication.shared.terminate(nil) },
            startDictation: { [weak self] in self?.startDictationFromPanel() }
        )
        let root = HistoryPanelView(store: history, actions: actions)
        popover.contentViewController = NSHostingController(rootView: root)
    }

    private func setupContextMenu() {
        let menu = NSMenu()
        let toggle = NSMenuItem(
            title: "Start Dictation", action: #selector(menuToggleDictation), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        toggleItem = toggle
        menu.addItem(.separator())
        let dockItem = NSMenuItem(
            title: "Floating pill", action: #selector(toggleDock), keyEquivalent: "")
        dockItem.target = self
        menu.addItem(dockItem)
        dockMenuItem = dockItem

        let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu(title: "Language")
        let current = UserDefaults.standard.string(forKey: "speak.language") ?? ""
        for (title, code) in [
            ("Auto-detect", ""), ("English", "en"), ("Hindi", "hi"), ("Spanish", "es"),
            ("French", "fr"), ("German", "de"),
        ] {
            let item = NSMenuItem(
                title: title, action: #selector(languageSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = code == current ? .on : .off
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        let serverItem = NSMenuItem(
            title: "Server settings…", action: #selector(showServerSettings), keyEquivalent: "")
        serverItem.target = self
        menu.addItem(serverItem)

        menu.addItem(.separator())
        let previewItem = NSMenuItem(
            title: "Preview HUD", action: #selector(previewHUD), keyEquivalent: "")
        previewItem.target = self
        menu.addItem(previewItem)
        let checkItem = NSMenuItem(
            title: "Check Permissions…", action: #selector(checkPermissions), keyEquivalent: "")
        checkItem.target = self
        menu.addItem(checkItem)
        let accItem = NSMenuItem(
            title: "Grant Accessibility Access…", action: #selector(openAccessibilitySettings),
            keyEquivalent: "")
        accItem.target = self
        menu.addItem(accItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Speak", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.delegate = self
        contextMenu = menu
    }

    private func setupPill() {
        pill.configure(
            SpeakPill.Callbacks(
                toggleRecord: { [weak self] in self?.menuToggleDictation() },
                openHistory: { [weak self] anchor in self?.showPanel(from: anchor) },
                openSettings: { [weak self] anchor in self?.showContextMenu(from: anchor) },
                openMicMenu: { [weak self] anchor in self?.showMicMenu(from: anchor) },
                level: { [weak self] in self?.recorder.currentLevel() ?? 0 }
            ))
        pill.applyIdleVisibilityFromDefaults()
    }

    // Keep the "Floating pill" checkmark in sync when the menu opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === contextMenu else { return }
        dockMenuItem?.state = pill.idleVisible ? .on : .off
    }

    @objc private func toggleDock() { pill.toggleIdleVisible() }

    private func showPanel(from anchor: NSView) {
        panelPreviousApp = NSWorkspace.shared.frontmostApplication
        pill.setExpandedPinned(true)  // hold the pill open while the panel is up
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    func popoverDidClose(_ notification: Notification) {
        pill.setExpandedPinned(false)
    }

    private func showContextMenu(from anchor: NSView) {
        contextMenu.popUp(
            positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 6), in: anchor)
    }

    private func showMicMenu(from anchor: NSView) {
        let menu = NSMenu()
        let header = NSMenuItem(title: "Input device", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let current = AudioDevices.defaultInputID()
        for device in AudioDevices.inputDevices() {
            let item = NSMenuItem(
                title: device.name, action: #selector(micDeviceSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.id
            item.state = device.id == current ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 6), in: anchor)
    }

    @objc private func micDeviceSelected(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? AudioDeviceID else { return }
        AudioDevices.setDefaultInput(id)
    }

    @objc private func showServerSettings() {
        let alert = NSAlert()
        alert.messageText = "Server settings"
        alert.informativeText = "Point Speak at your hosted backend. Leave empty for local."

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 96))
        let urlLabel = NSTextField(labelWithString: "Backend URL")
        urlLabel.frame = NSRect(x: 0, y: 74, width: 340, height: 16)
        urlLabel.font = .systemFont(ofSize: 11)
        urlLabel.textColor = .secondaryLabelColor
        let urlField = NSTextField(frame: NSRect(x: 0, y: 50, width: 340, height: 24))
        urlField.placeholderString = "https://your-app.up.railway.app"
        urlField.stringValue = UserDefaults.standard.string(forKey: "speak.backendURL") ?? ""
        let tokenLabel = NSTextField(labelWithString: "Access token (X-Speak-Token)")
        tokenLabel.frame = NSRect(x: 0, y: 26, width: 340, height: 16)
        tokenLabel.font = .systemFont(ofSize: 11)
        tokenLabel.textColor = .secondaryLabelColor
        let tokenField = NSTextField(frame: NSRect(x: 0, y: 2, width: 340, height: 24))
        tokenField.placeholderString = "leave empty for local"
        tokenField.stringValue = UserDefaults.standard.string(forKey: "speak.accessToken") ?? ""
        [urlLabel, urlField, tokenLabel, tokenField].forEach { container.addSubview($0) }
        alert.accessoryView = container

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let ws = CharacterSet.whitespacesAndNewlines
        UserDefaults.standard.set(
            urlField.stringValue.trimmingCharacters(in: ws), forKey: "speak.backendURL")
        UserDefaults.standard.set(
            tokenField.stringValue.trimmingCharacters(in: ws), forKey: "speak.accessToken")
    }

    @objc private func languageSelected(_ sender: NSMenuItem) {
        let code = (sender.representedObject as? String) ?? ""
        UserDefaults.standard.set(code, forKey: "speak.language")
        sender.menu?.items.forEach {
            $0.state = ($0.representedObject as? String) == code ? .on : .off
        }
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            contextMenu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.height + 5), in: sender)
        } else if state == .recording {
            // While a (panel-started) recording is in progress, left-click stops it.
            stopDictation()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Remember who was frontmost so a panel-triggered dictation targets them.
            panelPreviousApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    /// Start dictation from the panel: close it, return focus to the previous app,
    /// then record. Stop by left-clicking the menu-bar icon (or it auto-caps).
    private func startDictationFromPanel() {
        popover.performClose(nil)
        let previous = panelPreviousApp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            previous?.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.startDictation()
            }
        }
    }

    private func refreshStatusIcon() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: state.symbol, accessibilityDescription: state.tooltip)
        button.toolTip = state.tooltip
        toggleItem?.title = state == .recording ? "Stop Dictation" : "Start Dictation"
        toggleItem?.isEnabled = state != .processing
    }

    // MARK: - Dictation flow

    @objc private func menuToggleDictation() {
        state == .recording ? stopDictation() : startDictation()
    }

    private func startDictation() {
        guard state == .idle else { return }
        targetAppName = NSWorkspace.shared.frontmostApplication?.localizedName
        do {
            try recorder.start()
            state = .recording
            pill.showRecording()
            NSLog("Speak: recording started (target=\(targetAppName ?? "?"))")
            // Safety cap so a stuck recording can't exceed the model's limit.
            maxDurationTimer?.invalidate()
            maxDurationTimer = Timer.scheduledTimer(
                withTimeInterval: maxRecordingSeconds, repeats: false
            ) { [weak self] _ in
                NSLog("Speak: max recording duration reached, auto-stopping")
                self?.stopDictation()
            }
        } catch {
            NSLog("Speak: failed to start recording: \(error)")
            state = .idle
        }
    }

    private func stopDictation() {
        guard state == .recording else { return }
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        state = .processing
        NSLog("Speak: recording stopped, transcribing…")
        guard let fileURL = recorder.stop() else {
            NSLog("Speak: recording too short / empty, nothing to transcribe")
            pill.returnToIdle()
            state = .idle
            return
        }
        pill.showTranscribing()

        Task {
            do {
                let text = try await transcriber.transcribe(
                    fileURL: fileURL, appContext: targetAppName)
                await MainActor.run {
                    if text.isEmpty {
                        self.pill.returnToIdle()
                        return
                    }
                    self.history.add(text)
                    if self.inserter.insert(text) == .inserted {
                        self.pill.showSuccessThenHide()
                    } else {
                        // Couldn't find any text field — don't lose it: copy + toast.
                        self.pill.returnToIdle()
                        self.copyToast.show(text)
                    }
                }
            } catch {
                NSLog("Speak: transcription failed: \(error)")
                await MainActor.run {
                    self.pill.returnToIdle()
                    self.showError(error)
                }
            }
            await MainActor.run { self.state = .idle }
        }
    }

    // MARK: - Menu actions

    @objc private func previewHUD() {
        // Cycle the pill through its states so it can be inspected/screenshotted.
        pill.preview()
    }

    @objc private func checkPermissions() {
        let acc = Permissions.hasAccessibility(prompt: false)
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let micText: String
        switch mic {
        case .authorized: micText = "granted"
        case .denied: micText = "denied — enable in Privacy & Security › Microphone"
        case .restricted: micText = "restricted"
        case .notDetermined: micText = "not yet requested (dictate once to trigger the prompt)"
        @unknown default: micText = "unknown"
        }

        let alert = NSAlert()
        alert.messageText = "Speak permissions"
        alert.informativeText =
            "Microphone: \(micText)\n\n"
            + "Accessibility: \(acc ? "granted ✅" : "NOT granted ❌")\n\n"
            + (acc
                ? "Hotkey and paste are ready. Hold Right Option in any text field and speak."
                : "Enable Speak in System Settings › Privacy & Security › Accessibility, "
                    + "then QUIT and reopen the app (the grant only applies on relaunch).")
        alert.alertStyle = acc ? .informational : .warning
        alert.runModal()
    }

    @objc private func openAccessibilitySettings() {
        _ = Permissions.hasAccessibility(prompt: true)
        if let url = URL(
            string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Alerts

    private enum PermissionKind { case microphone, accessibility }

    private func showPermissionAlert(kind: PermissionKind) {
        let alert = NSAlert()
        switch kind {
        case .microphone:
            alert.messageText = "Microphone access needed"
            alert.informativeText =
                "Speak needs the microphone to record your voice. Enable it in "
                + "System Settings › Privacy & Security › Microphone."
        case .accessibility:
            alert.messageText = "Accessibility access needed"
            alert.informativeText =
                "Speak needs Accessibility access to detect the dictation hotkey and to "
                + "paste text into other apps. Enable Speak in System Settings › "
                + "Privacy & Security › Accessibility, then relaunch."
        }
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Dictation failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
