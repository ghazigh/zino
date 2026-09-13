"""The agent contract.

An agent is anything that can turn a conversation into a stream of events. The
gateway does not care whether an agent calls an LLM, queries a database, or
returns a constant — that is what makes agents composable and testable.
"""

from __future__ import annotations

import abc
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Literal

from zino_agents.openai_compat import ChatMessage

EventKind = Literal["content", "status", "error"]


@dataclass(slots=True)
class AgentEvent:
    """One unit of agent output.

    ``content`` is assistant text destined for the chat transcript. ``status`` is
    progress narration (tool calls, retries) — surfacing it is what makes a
    multi-step agent legible instead of a long silence. ``error`` terminates the
    run with a message the user is allowed to see.
    """

    kind: EventKind
    text: str

    @classmethod
    def content(cls, text: str) -> AgentEvent:
        return cls("content", text)

    @classmethod
    def status(cls, text: str) -> AgentEvent:
        return cls("status", text)

    @classmethod
    def error(cls, text: str) -> AgentEvent:
        return cls("error", text)


@dataclass(slots=True)
class RunContext:
    """Per-request context handed to an agent."""

    # Open WebUI forwards the signed-in user's identifier as `user`.
    user: str | None = None
    temperature: float | None = None
    max_tokens: int | None = None


class Agent(abc.ABC):
    """Base class for every ZINO agent."""

    #: Model id exposed to Open WebUI. Shows up in the model picker.
    id: str
    #: Human-readable label.
    name: str
    #: One line describing what this agent is for.
    description: str = ""

    @abc.abstractmethod
    def run(self, messages: list[ChatMessage], ctx: RunContext) -> AsyncIterator[AgentEvent]:
        """Stream the agent's response to ``messages``.

        Implemented as an ``async def`` generator in subclasses. Declared here as
        a plain method returning an iterator so subclasses are free to return any
        async iterable.
        """
        raise NotImplementedError
