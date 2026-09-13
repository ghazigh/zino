"""The general-purpose ZINO agent: an LLM with a tool-calling loop.

Streams from an upstream OpenAI-compatible provider, accumulating any tool calls
the model emits, executing them against the ZINO tool registry, and feeding the
results back until the model produces a final answer or the iteration budget is
spent.
"""

from __future__ import annotations

import asyncio
import json
import logging
from collections.abc import AsyncIterator
from typing import Any

import httpx

from zino_agents.agents.base import Agent, AgentEvent, RunContext
from zino_agents.config import settings
from zino_agents.openai_compat import ChatMessage
from zino_agents.tools import registry

log = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are ZINO, a personal agentic assistant.

You have tools available. Use them whenever the answer depends on information you
cannot reliably produce yourself — the current time, arithmetic, or anything a
tool exposes directly. Prefer calling a tool over guessing.

Be direct. Answer what was asked without restating the question."""


class AssistantAgent(Agent):
    id = "zino-assistant"
    name = "ZINO Assistant"
    description = "General-purpose agent with tool access."

    def __init__(self, client: httpx.AsyncClient | None = None) -> None:
        self._client = client

    async def _post_stream(self, payload: dict[str, Any]) -> AsyncIterator[dict[str, Any]]:
        """Yield parsed SSE chunk bodies from the upstream provider."""
        client = self._client or httpx.AsyncClient(timeout=settings.request_timeout_s)
        owns_client = self._client is None
        headers = {"Content-Type": "application/json"}
        if settings.upstream_api_key:
            headers["Authorization"] = f"Bearer {settings.upstream_api_key}"

        try:
            async with client.stream(
                "POST",
                f"{settings.upstream_base_url.rstrip('/')}/chat/completions",
                json=payload,
                headers=headers,
            ) as response:
                if response.status_code >= 400:
                    body = (await response.aread()).decode("utf-8", "replace")
                    raise UpstreamError(response.status_code, body)
                async for line in response.aiter_lines():
                    if not line.startswith("data: "):
                        continue
                    data = line[len("data: ") :].strip()
                    if data == "[DONE]":
                        return
                    try:
                        yield json.loads(data)
                    except json.JSONDecodeError:
                        log.warning("skipping malformed SSE chunk from upstream")
        finally:
            if owns_client:
                await client.aclose()

    async def run(self, messages: list[ChatMessage], ctx: RunContext) -> AsyncIterator[AgentEvent]:
        if not settings.upstream_api_key:
            yield AgentEvent.error(
                "ZINO_UPSTREAM_API_KEY is not configured, so this agent cannot reach a "
                "model provider. Set it in the environment, or use the ZINO Echo model "
                "to verify connectivity."
            )
            return

        convo: list[dict[str, Any]] = [{"role": "system", "content": SYSTEM_PROMPT}]
        convo += [
            m.model_dump(exclude_none=True, include={"role", "content", "name", "tool_call_id"})
            for m in messages
            if m.role != "system"
        ]

        for iteration in range(settings.max_tool_iterations):
            payload: dict[str, Any] = {
                "model": settings.upstream_model,
                "messages": convo,
                "stream": True,
            }
            if registry.specs():
                payload["tools"] = registry.specs()
            if ctx.temperature is not None:
                payload["temperature"] = ctx.temperature
            if ctx.max_tokens is not None:
                payload["max_tokens"] = ctx.max_tokens

            pending_calls: dict[int, dict[str, Any]] = {}
            assistant_text: list[str] = []
            finish_reason: str | None = None

            try:
                async for body in self._post_stream(payload):
                    choices = body.get("choices") or []
                    if not choices:
                        continue
                    choice = choices[0]
                    delta = choice.get("delta") or {}

                    if content := delta.get("content"):
                        assistant_text.append(content)
                        yield AgentEvent.content(content)

                    for call in delta.get("tool_calls") or []:
                        _accumulate_tool_call(pending_calls, call)

                    if choice.get("finish_reason"):
                        finish_reason = choice["finish_reason"]
            except UpstreamError as exc:
                log.error("upstream error %s: %s", exc.status, exc.body[:500])
                yield AgentEvent.error(exc.user_message())
                return
            except httpx.HTTPError as exc:
                log.error("upstream transport error: %s", exc)
                yield AgentEvent.error("Could not reach the model provider. Try again.")
                return

            if finish_reason != "tool_calls" or not pending_calls:
                return

            convo.append(
                {
                    "role": "assistant",
                    "content": "".join(assistant_text) or None,
                    "tool_calls": [pending_calls[i] for i in sorted(pending_calls)],
                }
            )

            for index in sorted(pending_calls):
                call = pending_calls[index]
                name = call["function"]["name"]
                yield AgentEvent.status(f"calling tool: {name}")
                result = await _execute_tool(call)
                convo.append({"role": "tool", "tool_call_id": call["id"], "content": result})

            log.info("tool iteration %d complete (%d calls)", iteration + 1, len(pending_calls))

        yield AgentEvent.error(
            f"Stopped after {settings.max_tool_iterations} tool rounds without a final "
            "answer. This usually means the agent is looping on a failing tool."
        )


class UpstreamError(Exception):
    def __init__(self, status: int, body: str) -> None:
        super().__init__(f"upstream returned {status}")
        self.status = status
        self.body = body

    def user_message(self) -> str:
        """Error text safe to show a user — never echoes the upstream body,
        which can contain organisation or key details."""
        if self.status in (401, 403):
            return "The model provider rejected ZINO's credentials. Check ZINO_UPSTREAM_API_KEY."
        if self.status == 429:
            return "The model provider is rate-limiting ZINO. Try again shortly."
        return f"The model provider returned an error (HTTP {self.status})."


def _accumulate_tool_call(pending: dict[int, dict[str, Any]], delta_call: dict[str, Any]) -> None:
    """Merge a streamed tool-call fragment into the accumulator.

    Providers split one tool call across many chunks: the first carries the id
    and name, later ones append argument text. Fragments are keyed by ``index``.
    """
    index = delta_call.get("index", 0)
    slot = pending.setdefault(
        index,
        {"id": "", "type": "function", "function": {"name": "", "arguments": ""}},
    )
    if call_id := delta_call.get("id"):
        slot["id"] = call_id
    fn = delta_call.get("function") or {}
    if name := fn.get("name"):
        slot["function"]["name"] = name
    if args := fn.get("arguments"):
        slot["function"]["arguments"] += args


async def _execute_tool(call: dict[str, Any]) -> str:
    """Run one tool call, converting every failure into text the model can read.

    A tool that raises must not kill the run: the model needs to see the error so
    it can correct the call or route around it.
    """
    name = call["function"]["name"]
    tool = registry.get(name)
    if tool is None:
        return f"Error: no tool named {name!r} is available."

    raw_args = call["function"]["arguments"] or "{}"
    try:
        kwargs = json.loads(raw_args)
    except json.JSONDecodeError:
        return f"Error: arguments for {name!r} were not valid JSON."
    if not isinstance(kwargs, dict):
        return f"Error: arguments for {name!r} must be a JSON object."

    try:
        return await asyncio.wait_for(tool.fn(**kwargs), timeout=settings.request_timeout_s)
    except TypeError as exc:
        return f"Error: invalid arguments for {name!r}: {exc}"
    except TimeoutError:
        return f"Error: tool {name!r} timed out."
    except Exception as exc:  # noqa: BLE001 - tool failures are data, not crashes
        log.exception("tool %s raised", name)
        return f"Error: tool {name!r} failed: {type(exc).__name__}: {exc}"
