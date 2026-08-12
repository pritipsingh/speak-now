"""
Speak — AgentOS entrypoint
==========================

Backend for the Speak dictation app. It runs a single dictation cleanup agent and
exposes the custom speech-to-text route (`/dictation/transcribe`), which chains
OpenAI gpt-4o-transcribe into that agent.
"""

from os import getenv

from agno.os import AgentOS
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from agents.dictation import dictation_agent
from app.dictation_api import router as dictation_router
from db import get_postgres_db
from workflows.dictation import dictation_workflow

# Local dev (RUNTIME_ENV=dev, set by compose.yaml) serves without JWT auth.
runtime_env = getenv("RUNTIME_ENV", "prd")

# Shared-secret gate for small-team hosting. When SPEAK_ACCESS_TOKEN is set, every
# request must carry `X-Speak-Token: <token>` except the open paths below. Unset
# (local dev) → no gate. This lets us host on Railway with RUNTIME_ENV=dev (AgentOS
# JWT off) while still keeping the endpoint private behind one secret.
SPEAK_ACCESS_TOKEN = getenv("SPEAK_ACCESS_TOKEN", "")
_OPEN_PATHS = ("/health", "/docs", "/redoc", "/openapi.json", "/dictation/health")

# Custom (non-agent) routes must be registered on a base_app so they land ahead of
# the catch-all sub-app AgentOS mounts at "/" (otherwise they 404 on dispatch).
base_app = FastAPI()
base_app.include_router(dictation_router)


@base_app.middleware("http")
async def require_shared_secret(request: Request, call_next):
    if SPEAK_ACCESS_TOKEN:
        path = request.url.path
        if not any(path.startswith(p) for p in _OPEN_PATHS):
            if request.headers.get("X-Speak-Token") != SPEAK_ACCESS_TOKEN:
                return JSONResponse({"detail": "Unauthorized"}, status_code=401)
    return await call_next(request)


agent_os = AgentOS(
    name="Speak",
    authorization=runtime_env != "dev",
    db=get_postgres_db(),
    agents=[dictation_agent],
    workflows=[dictation_workflow],
    base_app=base_app,
    telemetry=False,
)
app = agent_os.get_app()


if __name__ == "__main__":
    agent_os.serve(app="app.main:app", reload=False)
