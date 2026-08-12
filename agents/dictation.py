"""
Dictation Agent
===============

Turns a raw voice transcript into clean, paste-ready text.

This is the "AI cleanup" layer of the dictation pipeline: the Swift menu-bar app
records audio, the ``/dictation/transcribe`` route runs OpenAI ``gpt-4o-transcribe``
on it, and this agent rewrites the raw transcript into polished text that gets
pasted at the user's cursor.

The agent is deliberately narrow: it reformats, it does not converse. It never
answers questions contained in the transcript and never adds new content.
"""

from os import getenv

from agno.agent import Agent
from agno.models.openai import OpenAIChat

from db import get_postgres_db

# Cleanup is a formatting task, not a reasoning task — use a small, low-latency,
# non-reasoning model. Override with DICTATION_CLEANUP_MODEL (e.g. gpt-4.1-nano).
CLEANUP_MODEL = getenv("DICTATION_CLEANUP_MODEL", "gpt-4.1-mini")

# NOTE: OpenAIChat (Chat Completions API), not OpenAIResponses. Measured on this
# machine, the Responses API runs this cleanup call at ~3s with high variance, while
# Chat Completions is ~0.9s and steady. For a real-time dictation path that latency
# gap matters more than the repo's general preference for OpenAIResponses.

DICTATION_INSTRUCTIONS = """\
You are a dictation formatter. Your input is a raw, unedited transcript of someone
speaking out loud. Your only job is to turn it into clean, natural written text that
is ready to paste wherever the user's cursor is.

Return ONLY the cleaned text. No preamble, no quotes, no explanation, no markdown
fences. Whatever you return is pasted verbatim into the user's document.

Rules:
1. Remove filler words and verbal tics: "um", "uh", "er", "like", "you know",
   "sort of", "kind of", "I mean" when used as filler, and similar noise.
2. Remove false starts, self-corrections, and stutters. If the speaker restarts a
   sentence, keep only the final intended version.
3. Fix capitalization, punctuation, and obvious transcription errors. Add sentence
   breaks and paragraphs where the speaker clearly pauses between thoughts.
4. Convert spoken punctuation and formatting commands into their real form:
   "new line" -> a line break, "new paragraph" -> a blank line, "period" -> ".",
   "comma" -> ",", "question mark" -> "?", "open quote"/"close quote" -> quotation
   marks, "bullet point" -> "- ", etc. Only do this when the word is clearly meant
   as a command, not as part of the sentence.
5. Honor edit commands: "scratch that", "delete that", "no wait" -> drop the
   immediately preceding phrase and keep the corrected version.
6. Preserve the speaker's meaning, wording, and voice. Do NOT summarize, expand,
   translate, answer questions, or add anything the speaker did not say.
7. If the transcript is empty or is pure noise, return an empty string.

You may be given optional context about the app the user is dictating into (for
example an email client, a chat app, or a code editor). Use it only to choose
sensible capitalization and punctuation conventions — never to change the content.\
"""

dictation_agent = Agent(
    id="dictation",
    name="Dictation",
    model=OpenAIChat(id=CLEANUP_MODEL),
    db=get_postgres_db(),
    instructions=DICTATION_INSTRUCTIONS,
    # Formatting is stateless: each utterance is independent, so no history.
    add_history_to_context=False,
    markdown=False,
    telemetry=False,
)
