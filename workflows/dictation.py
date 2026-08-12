"""
Dictation Workflow
==================

The dictation pipeline as an agno Workflow — two explicit steps:

    Step 1 (function): transcribe audio  ->  raw text   (OpenAI gpt-4o-transcribe)
    Step 2 (agent):    cleanup raw text  ->  paste-ready text

The audio bytes are passed in via ``additional_data`` (workflow inputs are
text-oriented, so binary audio rides alongside). The cleanup agent step receives
the transcribe step's output as its input automatically.
"""

from __future__ import annotations

from os import getenv
from typing import Optional

from agno.workflow import Step, StepInput, StepOutput, Workflow
from openai import AsyncOpenAI

from agents.dictation import dictation_agent
from db import get_postgres_db

TRANSCRIBE_MODEL = getenv("DICTATION_TRANSCRIBE_MODEL", "gpt-4o-transcribe")

_client: Optional[AsyncOpenAI] = None


def _openai() -> AsyncOpenAI:
    global _client
    if _client is None:
        _client = AsyncOpenAI()
    return _client


async def transcribe_audio(filename: str, data: bytes, language: Optional[str]) -> str:
    """Speech-to-text. Reused by the /transcribe route for the clean=false path."""
    client = _openai()
    file_arg = (filename or "audio.wav", data)
    if language:
        result = await client.audio.transcriptions.create(model=TRANSCRIBE_MODEL, file=file_arg, language=language)
    else:
        result = await client.audio.transcriptions.create(model=TRANSCRIBE_MODEL, file=file_arg)
    return (getattr(result, "text", "") or "").strip()


async def _transcribe_step(step_input: StepInput) -> StepOutput:
    """Step 1: read the audio from additional_data and transcribe it."""
    data = step_input.additional_data or {}
    audio_bytes: bytes = data.get("audio_bytes") or b""
    filename: str = data.get("filename") or "audio.wav"
    language: Optional[str] = data.get("language")

    raw = await transcribe_audio(filename, audio_bytes, language)

    # Surface the raw transcript to the caller (the workflow's final content is the
    # cleaned text from step 2).
    sink = data.get("sink")
    if isinstance(sink, dict):
        sink["raw"] = raw

    return StepOutput(content=raw)


# Step 1 transcribes, Step 2 cleans. The agent step auto-receives step 1's output.
dictation_workflow = Workflow(
    id="dictation-pipeline",
    name="Dictation Pipeline",
    description="Transcribe audio, then clean it into paste-ready text.",
    db=get_postgres_db(),
    steps=[
        Step(name="transcribe", executor=_transcribe_step),
        Step(name="cleanup", agent=dictation_agent),
    ],
)
