import AVFoundation
import AppKit
import ApplicationServices

/// Microphone and Accessibility permission helpers.
enum Permissions {

    /// Request microphone access. The completion is called with the granted flag.
    static func requestMicrophone(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in completion(granted) }
        default:
            completion(false)
        }
    }

    /// Whether the app is trusted for Accessibility (needed for the global hotkey and
    /// for posting keystrokes to other apps). When `prompt` is true, macOS shows the
    /// system dialog that deep-links into Privacy & Security settings.
    @discardableResult
    static func hasAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
