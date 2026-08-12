import AppKit

/// Global push-to-talk hotkey.
///
/// Watches for the Right Option (⌥) key being pressed and released anywhere in the
/// system. Uses a global event monitor on `.flagsChanged`, which requires
/// Accessibility permission.
///
/// In a `flagsChanged` event, `keyCode` identifies which physical modifier changed
/// (61 = right option, 58 = left option) and the modifier flags tell us whether it
/// is now down or up.
final class HotkeyManager {
    private let onPress: () -> Void
    private let onRelease: () -> Void
    private var monitor: Any?
    private var isDown = false

    /// keyCode for the Right Option key.
    private let triggerKeyCode: UInt16 = 61

    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
    }

    func start() {
        // Global monitor: fires for events delivered to other apps (never our own).
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) {
            [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == triggerKeyCode else { return }
        // The Option flag is present while the key is held.
        let down = event.modifierFlags.contains(.option)
        if down && !isDown {
            isDown = true
            NSLog("Speak: hotkey down (Right Option)")
            onPress()
        } else if !down && isDown {
            isDown = false
            NSLog("Speak: hotkey up (Right Option)")
            onRelease()
        }
    }

    deinit { stop() }
}
