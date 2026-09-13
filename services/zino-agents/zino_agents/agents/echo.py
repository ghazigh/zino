"""A reference agent with no external dependencies.

Its job is to prove the whole path works — Open WebUI to gateway to stream —
without an upstream API key or network access. Keep it working; it is what the
smoke test and a fresh `docker compose up` rely on.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

from zino_agents.agents.base import Agent, AgentEvent, RunContext
from zino_agents.openai_compat import ChatMessage


class EchoAgent(Agent):
    id = "zino-echo"
    name = "ZINO Echo"
    description = "Connectivity check. Repeats your message back, word by word."

    async def run(self, messages: list[ChatMessage], ctx: RunContext) -> AsyncIterator[AgentEvent]:
        last_user = next(
            (m for m in reversed(messages) if m.role == "user"),
            None,
        )
        if last_user is None:
            yield AgentEvent.content("No user message to echo.")
            return

        yield AgentEvent.status("echo: streaming back your message")
        text = last_user.text()
        if not text.strip():
            yield AgentEvent.content("(empty message)")
            return

        # Stream word by word so the client-side streaming path is exercised,
        # not just the final payload.
        for i, word in enumerate(text.split()):
            yield AgentEvent.content(word if i == 0 else f" {word}")
