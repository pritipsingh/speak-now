import AppKit

// WisprFlow — a Wispr Flow-like push-to-talk dictation app for macOS.
//
// Hold the hotkey (Right Option by default), speak, release. The audio is sent to
// the AgentOS backend, transcribed with gpt-4o-transcribe, cleaned up by the agno
// dictation agent, and pasted at the cursor in whatever app is frontmost.
//
// Runs as a menu-bar accessory app (no Dock icon).

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
