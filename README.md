# Speak — a Wispr Flow-like dictation app for macOS

Hold a hotkey, speak, release — Speak transcribes your voice, cleans it up, and pastes
the result at your cursor in **any app**. A native macOS menu-bar app on top of an
[agno](https://docs.agno.com) / AgentOS backend.

- **Speech-to-text:** OpenAI `gpt-4o-transcribe`
- **Cleanup:** an agno agent (`gpt-4.1-mini`) removes fillers, fixes punctuation, and
  turns spoken commands ("new line", "period") into real formatting
- **Insertion:** finds the focused field (or the nearest one to your pointer) and pastes

```
Hold Right Option → record → POST audio → [ transcribe → cleanup ] → paste at cursor
        (Swift app)                              (agno workflow)         (Swift app)
```

## Repo layout

| Path | What |
|------|------|
| `agents/dictation.py` | The cleanup agent (formatting-only instructions) |
| `workflows/dictation.py` | 2-step agno Workflow: transcribe → cleanup |
| `app/dictation_api.py` | `POST /dictation/transcribe` (audio → text) |
| `app/main.py` | AgentOS setup + shared-secret gate |
| `mac-app/` | The native Swift menu-bar app |

## Prerequisites

- **Backend:** [Docker](https://www.docker.com/) + an **OpenAI API key**
- **Mac app:** macOS 13+, Xcode **Command Line Tools** (`xcode-select --install`) — no full Xcode needed

## 1. Run the backend (local)

```bash
cp example.env .env
# edit .env → set OPENAI_API_KEY=sk-...your real key...
docker compose up -d
```

Verify: `curl http://127.0.0.1:8000/dictation/health` → `{"status":"ok",...}`.
Interactive API docs: http://127.0.0.1:8000/docs

> Prefer to host it so others can use it? See **[DEPLOY_RAILWAY.md](DEPLOY_RAILWAY.md)**.

## 2. Build & run the Mac app

```bash
cd mac-app
./setup_signing.sh    # once — creates a stable local signing identity (grants persist)
./build_app.sh        # compiles + assembles Speak.app
open Speak.app
```

A **microphone icon** appears in the menu bar.

**First launch — grant two permissions:**
1. **Microphone** — prompted on first dictation.
2. **Accessibility** — required for the hotkey *and* to paste into other apps. Enable
   **Speak** in System Settings › Privacy & Security › Accessibility, then relaunch.
   (Menu bar → right-click → "Check Permissions…" shows the status.)

**Use it:** put your cursor in any text field, **hold Right Option**, speak, release.

## 3. Point the app at your backend (if hosted)

Right-click the menu-bar icon → **Server settings…** → set the Backend URL
(`https://…`) and the Access token (matches `SPEAK_ACCESS_TOKEN` on the server).
Local dev needs neither.

## Controls

- **Hotkey:** hold Right Option (push-to-talk).
- **Left-click** the menu-bar icon → history panel (search, click to re-copy).
- **Right-click** → controls: dictation toggle, **Floating pill** (draggable dock),
  **Language** (Auto / English / Hindi / …), Server settings, permissions.
- **Floating pill:** a small orb that expands on hover and morphs into the waveform
  while recording.

## Download (no build)

Grab `Speak.dmg` from the [Releases](../../releases) page and drag Speak into
Applications. The app is currently **self-signed**, so a downloaded copy is quarantined
by macOS — clear it once:

```bash
xattr -dr com.apple.quarantine /Applications/Speak.app
```

(For a clean, no-bypass download, the app needs an Apple Developer ID + notarization.)

## Notes

- The `/dictation/transcribe` route exists because the input is a **binary audio
  upload**, which the generic agno run/workflow endpoints don't accept. It keeps your
  OpenAI key server-side.
- Every cleanup run is persisted to Postgres (visible in `/sessions` and at
  [os.agno.com](https://os.agno.com)).
- Built on the [agentos-docker](https://github.com/agno-agi/agentos-docker) template.
