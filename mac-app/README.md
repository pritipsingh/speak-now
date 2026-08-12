# WisprFlow: a Wispr Flow-like dictation app

Hold a hotkey, speak, release. Your speech is transcribed, cleaned up by an agno
agent, and pasted at the cursor in **whatever app is frontmost**: email, Slack,
a code editor, a text field, anywhere.

```
 ┌─────────────────────────── macOS ───────────────────────────┐
 │  Hold Right Option (⌥)                                       │
 │      │                                                       │
 │      ▼                                                       │
 │  🎙  AVAudioRecorder  ──►  m4a  ──►  POST /dictation/transcribe
 │                                              │  (AgentOS backend)
 │                                              ▼
 │                              gpt-4o-transcribe → dictation agent
 │                                              │
 │      ⌘V paste at cursor  ◄────────  cleaned text
 └──────────────────────────────────────────────────────────────┘
```

- **Frontend** (this folder): native Swift menu-bar app: global hotkey, mic
  capture, cursor text insertion.
- **Backend** (`../`, the AgentOS template): `POST /dictation/transcribe` runs
  OpenAI `gpt-4o-transcribe`, then the `dictation` agno agent
  (`../agents/dictation.py`) rewrites the raw transcript into clean, paste-ready
  text.

## Prerequisites

- macOS 13+ (you're on 14). Command Line Tools are enough, **no full Xcode needed**.
- The AgentOS backend running (see below).

## 1. Run the backend

The backend is the AgentOS template one level up. It needs a **valid
`OPENAI_API_KEY`** in `../.env` (the template ships a `sk-***` placeholder, replace
it with your real key).

```bash
cd ..
# edit .env: set OPENAI_API_KEY=sk-...your real key...
docker compose up -d
```

> **Port note:** this Mac already runs a `demo-os` stack on port **8000**. Either
> stop it (`docker stop demo-os-api`) so the dictation backend can use 8000, or run
> the backend on another host port and point the app at it with
> `WISPR_BACKEND_URL` (see below).

Verify: `curl http://127.0.0.1:8000/dictation/health` → `{"status":"ok",...}`

## 2. Build & run the app

```bash
./build_app.sh          # compiles + assembles WisprFlow.app (ad-hoc signed)
open WisprFlow.app
```

A **microphone icon** appears in the menu bar.

### First-launch permissions (required)

macOS will ask for two grants, both are needed:

1. **Microphone**, to record your voice.
2. **Accessibility**, to detect the global hotkey *and* to paste into other apps.
   Enable **WisprFlow** in System Settings › Privacy & Security › Accessibility,
   then relaunch the app. (Menu → "Grant Accessibility Access…" opens the pane.)

### Use it

Put your cursor in any text field, **hold Right Option (⌥)**, speak, release.
The cleaned text is pasted where your cursor is.

There's also a menu item ("Start / Stop Dictation") to toggle without the hotkey,
handy for testing before Accessibility is granted.

## Configuration

| What | How |
|------|-----|
| Backend URL | `WISPR_BACKEND_URL` env var (default `http://127.0.0.1:8000`) |
| Hotkey | `triggerKeyCode` in `Sources/WisprFlow/HotkeyManager.swift` (61 = Right Option) |
| Skip AI cleanup | send `clean=false`, see `TranscriptionClient.swift` |
| STT model | `DICTATION_TRANSCRIBE_MODEL` env var on the backend |

> Env vars are inherited only when you launch the **binary from a terminal**
> (`./WisprFlow.app/Contents/MacOS/WisprFlow`), not via `open`. To change the
> backend URL for a GUI launch, edit the default in `TranscriptionClient.swift`.

## Known limitations (MVP)

- Paste-based insertion uses the clipboard (saved and restored). A field that
  ignores ⌘V won't receive text.
- Batch transcription (record → send on release), not live streaming. Deepgram-style
  streaming is a natural next step.
- No custom-vocabulary, per-app tone profiles, or history yet.
