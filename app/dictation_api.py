"""
Dictation API
=============

Custom FastAPI routes for the dictation (Wispr Flow-like) feature.

The custom route is needed because the input is a binary audio upload, which the
agno run/workflow endpoints don't accept. It receives the audio and drives the
dictation workflow:

    audio bytes  ->  [ transcribe step  ->  cleanup step ]  ->  text

The Swift menu-bar app records the microphone while a hotkey is held, then POSTs
the recorded audio here. The cleaned text is returned and pasted at the cursor.
"""

from __future__ import annotations

from os import getenv
from typing import Optional

from agno.utils.log import log_error, log_info
from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from pydantic import BaseModel

from workflows.dictation import TRANSCRIBE_MODEL, dictation_workflow, transcribe_audio


class DictationResponse(BaseModel):
    """What the Swift app receives back."""

    raw: str  # unedited transcript straight from the STT model
    text: str  # cleaned, paste-ready text (== raw when clean=false)
    cleaned: bool  # whether the cleanup step ran


router = APIRouter(prefix="/dictation", tags=["dictation"])


@router.post("/transcribe", response_model=DictationResponse)
async def transcribe(
    audio: UploadFile = File(..., description="Recorded audio (wav/mp3/m4a/webm)"),
    clean: bool = Form(True, description="Run the cleanup step"),
    language: Optional[str] = Form(None, description="ISO-639-1 hint, e.g. 'en'"),
    app_context: Optional[str] = Form(None, description="Frontmost app name (unused for now)"),
) -> DictationResponse:
    """Transcribe recorded audio and return clean, paste-ready text."""
    data = await audio.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty audio upload")
    filename = audio.filename or "audio.wav"

    # clean=false → speech-to-text only, no workflow needed.
    if not clean:
        try:
            raw = await transcribe_audio(filename, data, language)
        except Exception as exc:  # noqa: BLE001
            log_error(f"Transcription failed: {exc}")
            raise HTTPException(status_code=502, detail=f"Transcription failed: {exc}") from exc
        log_info(f"Dictation (raw only): {raw[:120]!r}")
        return DictationResponse(raw=raw, text=raw, cleaned=False)

    # clean=true → run the two-step dictation workflow.
    sink: dict = {}
    try:
        run = await dictation_workflow.arun(
            input="",
            additional_data={
                "audio_bytes": data,
                "filename": filename,
                "language": language,
                "sink": sink,
            },
        )
    except Exception as exc:  # noqa: BLE001
        log_error(f"Dictation workflow failed: {exc}")
        raise HTTPException(status_code=502, detail=f"Dictation failed: {exc}") from exc

    text = (run.content or "").strip()
    raw = (sink.get("raw") or text).strip()
    log_info(f"Dictation workflow: raw={raw[:80]!r} -> text={text[:80]!r}")
    return DictationResponse(raw=raw, text=text, cleaned=True)


@router.get("/health")
async def health() -> dict:
    """Cheap readiness probe for the Swift app to confirm the backend is up."""
    return {"status": "ok", "transcribe_model": TRANSCRIBE_MODEL}
