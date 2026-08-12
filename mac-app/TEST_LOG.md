# TEST_LOG — WisprFlow

### Backend: `POST /dictation/transcribe` route wiring

**Status:** PASS

**Description:** Booted the AgentOS stack (docker compose, remapped to host ports
8010/5433 to avoid colliding with the running `demo-os` stack). Verified the
dictation router mounts correctly. Initially the route 404'd on dispatch while
appearing in `openapi.json` — root cause: AgentOS mounts a catch-all sub-app at
`/` and routes appended after `get_app()` are shadowed by it. Fixed by registering
the router on a `FastAPI` `base_app` passed into `AgentOS(...)`, so the routes land
ahead of the mount.

**Result:** `GET /dictation/health` → `{"status":"ok","transcribe_model":"gpt-4o-transcribe"}`.
`POST /dictation/transcribe` reaches the full pipeline (STT → cleanup agent).

---

### Backend: end-to-end transcription

**Status:** PASS

**Description:** Synthesized a test clip with `say` ("um so I was thinking, you
know, we should uh ship the the dictation feature by friday period new line
thanks"), converted to m4a, and POSTed it to `/dictation/transcribe`.

**Result:** Full pipeline works. raw = "um so I was thinking you know we should
ship the dictation feature by Friday period new line thanks"; cleaned text = "I
was thinking we should ship the dictation feature by Friday.\nThanks." — fillers
removed, "period"→".", "new line"→line break.

Note: hit a 401 first because the `OPENAI_API_KEY` in `../.env` contained a stray
space (paste artifact, position 36 → 165 chars instead of 164). Removing the
whitespace fixed it. Also added `../compose.override.yaml` remapping the DB host
port to 5433 so the stack doesn't collide with the machine's `demo-os` DB on 5432.

---

### Frontend: Swift build & bundle

**Status:** PASS

**Description:** `swift build` (debug + release) compiles all sources against the
macOS SDK using Command Line Tools (no full Xcode). `./build_app.sh` assembles and
ad-hoc-signs `WisprFlow.app`.

**Result:** Build succeeds; `WisprFlow.app` produced. Live end-to-end run (hotkey →
speak → paste) requires a user with mic access and the permission grants, plus a
valid backend key — to be exercised manually.

---
