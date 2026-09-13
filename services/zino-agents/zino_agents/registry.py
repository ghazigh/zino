"""Agent registry — maps an OpenAI ``model`` id onto a ZINO agent."""

from __future__ import annotations

from zino_agents.agents.assistant import AssistantAgent
from zino_agents.agents.base import Agent
from zino_agents.agents.echo import EchoAgent
from zino_agents.openai_compat import ModelCard

# Importing builtin tools registers them as a side effect.
from zino_agents.tools import builtin  # noqa: F401


class AgentRegistry:
    def __init__(self, agents: list[Agent]) -> None:
        self._agents = {a.id: a for a in agents}

    def get(self, model_id: str) -> Agent | None:
        return self._agents.get(model_id)

    def cards(self) -> list[ModelCard]:
        return [
            ModelCard(id=a.id, name=a.name, description=a.description)
            for a in self._agents.values()
        ]

    def ids(self) -> list[str]:
        return list(self._agents)


registry = AgentRegistry([EchoAgent(), AssistantAgent()])
