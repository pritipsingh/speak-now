# Speak — a Wispr Flow-like dictation app for macOS

Hold a hotkey, speak, release — Speak transcribes your voice, cleans it up, and pastes
the result at your cursor in **any app**. A native macOS menu-bar app on top of an
[agno](https://docs.agno.com) / AgentOS backend.

- **Speech-to-text:** OpenAI `gpt-4o-transcribe`
- **Cleanup:** an agno agent (`gpt-4.1-mini`) removes fillers, fixes punctuation, and
  turns spoken commands ("new line", "period") into real formatting
- **Insertion:** finds the focused field (or the nearest one to your pointer) and pastes

## How it works

![How Speak works — hold Right Option, record, transcribe and clean, paste at cursor](docs/how-it-works.svg)

A single floating **pill** is the whole UI — a small orb that expands on hover and
morphs into the waveform while you dictate:

![Speak pill states — idle orb, hover controls, recording waveform, transcribing](docs/pill-states.svg)

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

## Swap the models — it's open source, experiment freely

Both models are one env var each. Try cheaper/faster models and compare quality vs
latency vs cost:

| Env var | Default | What it does | Try |
|---|---|---|---|
| `DICTATION_TRANSCRIBE_MODEL` | `gpt-4o-transcribe` | Speech-to-text | `gpt-4o-mini-transcribe` (faster/cheaper) |
| `DICTATION_CLEANUP_MODEL` | `gpt-4.1-mini` | Cleanup/formatting | `gpt-4.1-nano` (lowest latency) |

Set them in `.env` (or your host's variables) and restart:

```bash
DICTATION_TRANSCRIBE_MODEL=gpt-4o-mini-transcribe
DICTATION_CLEANUP_MODEL=gpt-4.1-nano
```

Want a **different provider** entirely? The cleanup step is a normal agno agent in
`agents/dictation.py` — swap `OpenAIChat` for `Claude`, `Gemini`, `Ollama` (local),
etc. (see [agno models](https://docs.agno.com/models)). The transcribe step is a plain
function in `workflows/dictation.py` — point it at Deepgram, Groq Whisper, or a local
`faster-whisper` instead. Because the pipeline is a two-step agno Workflow, adding steps
(language-detect, per-app tone, custom vocabulary) is just appending a `Step`.

Tip: the app can send `clean=false` to see the raw transcript, so you can measure STT
quality separately from the cleanup model.

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
