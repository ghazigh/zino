"""Pydantic models and helpers for the subset of the OpenAI API that ZINO speaks.

Open WebUI consumes ZINO as an OpenAI-compatible provider, so these shapes are a
contract with upstream, not an internal detail. Keep them permissive on input
(Open WebUI sends fields we ignore) and exact on output.
"""

from __future__ import annotations

import json
import time
import uuid
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


def _new_id(prefix: str) -> str:
    return f"{prefix}-{uuid.uuid4().hex[:24]}"


class ChatMessage(BaseModel):
    model_config = ConfigDict(extra="allow")

    role: Literal["system", "user", "assistant", "tool"]
    content: str | list[dict[str, Any]] | None = None
    name: str | None = None
    tool_call_id: str | None = None

    def text(self) -> str:
        """Flatten content to plain text.

        Open WebUI sends multimodal content as a list of parts; we concatenate
        the text parts and ignore the rest rather than failing the request.
        """
        if self.content is None:
            return ""
        if isinstance(self.content, str):
            return self.content
        return "".join(
            part.get("text", "")
            for part in self.content
            if isinstance(part, dict) and part.get("type") == "text"
        )


class ChatCompletionRequest(BaseModel):
    model_config = ConfigDict(extra="allow")

    model: str
    messages: list[ChatMessage]
    stream: bool = False
    temperature: float | None = None
    max_tokens: int | None = None
    user: str | None = None


class ModelCard(BaseModel):
    id: str
    object: Literal["model"] = "model"
    created: int = Field(default_factory=lambda: int(time.time()))
    owned_by: str = "zino"
    # Open WebUI surfaces this in the model picker.
    name: str | None = None
    description: str | None = None


class ModelList(BaseModel):
    object: Literal["list"] = "list"
    data: list[ModelCard]


def completion_response(model: str, content: str) -> dict[str, Any]:
    """A non-streaming ``chat.completion`` body."""
    return {
        "id": _new_id("chatcmpl"),
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model,
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": content},
                "finish_reason": "stop",
            }
        ],
        # Open WebUI tolerates absent usage, but sending zeros keeps its
        # stats panel from rendering "undefined".
        "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
    }


def chunk(completion_id: str, model: str, delta: dict[str, Any], finish: str | None = None) -> str:
    """Serialise one ``chat.completion.chunk`` as an SSE ``data:`` line."""
    body = {
        "id": completion_id,
        "object": "chat.completion.chunk",
        "created": int(time.time()),
        "model": model,
        "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
    }
    return f"data: {json.dumps(body, ensure_ascii=False)}\n\n"


def new_completion_id() -> str:
    return _new_id("chatcmpl")


DONE = "data: [DONE]\n\n"
