"""ZINO agent gateway HTTP surface.

Exposes the slice of the OpenAI API that Open WebUI needs, so ZINO's agents
appear in the model picker alongside any other provider.
"""

from __future__ import annotations

import logging
import secrets
from collections.abc import AsyncIterator

from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.responses import JSONResponse, StreamingResponse

from zino_agents import __version__
from zino_agents.agents.base import RunContext
from zino_agents.config import settings
from zino_agents.openai_compat import (
    DONE,
    ChatCompletionRequest,
    ModelList,
    chunk,
    completion_response,
    new_completion_id,
)
from zino_agents.registry import registry

logging.basicConfig(
    level=settings.log_level.upper(),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("zino.gateway")

app = FastAPI(
    title="ZINO Agent Gateway",
    version=__version__,
    description="ZINO agents, exposed over the OpenAI API shape.",
)


async def require_api_key(request: Request) -> None:
    """Validate the bearer token Open WebUI sends as its OpenAI API key."""
    if not settings.require_auth:
        return

    if not settings.api_key:
        # Production without a key configured: fail closed rather than serving
        # an unauthenticated agent endpoint to the internet.
        log.error("ZINO_API_KEY is unset in a production environment; refusing request")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Gateway is not configured for authenticated access.",
        )

    header = request.headers.get("authorization", "")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not secrets.compare_digest(token, settings.api_key):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API key.",
            headers={"WWW-Authenticate": "Bearer"},
        )


@app.get("/healthz", include_in_schema=False)
async def healthz() -> dict[str, object]:
    """Liveness probe. Unauthenticated by design — Cloud Run calls it."""
    return {"status": "ok", "version": __version__, "agents": registry.ids()}


@app.get("/v1/models", dependencies=[Depends(require_api_key)])
async def list_models() -> ModelList:
    return ModelList(data=registry.cards())


@app.post("/v1/chat/completions", dependencies=[Depends(require_api_key)])
async def chat_completions(req: ChatCompletionRequest):
    agent = registry.get(req.model)
    if agent is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Unknown model {req.model!r}. Available: {', '.join(registry.ids())}.",
        )

    ctx = RunContext(user=req.user, temperature=req.temperature, max_tokens=req.max_tokens)

    if req.stream:
        return StreamingResponse(
            _stream(agent, req, ctx),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                # Stops any intermediary from buffering the stream, which would
                # defeat token-by-token rendering in the UI.
                "X-Accel-Buffering": "no",
            },
        )

    parts: list[str] = []
    async for event in agent.run(req.messages, ctx):
        if event.kind == "content":
            parts.append(event.text)
        elif event.kind == "error":
            parts.append(f"\n\n**Error:** {event.text}")
    return JSONResponse(completion_response(req.model, "".join(parts)))


def _render_status(text: str) -> str:
    """Render a status event as chat content.

    The plain OpenAI protocol has no status channel, so progress is emitted as
    italic text on its own line — visible, but distinct from the answer.
    """
    return f"\n_{text}_\n"


async def _stream(agent, req: ChatCompletionRequest, ctx: RunContext) -> AsyncIterator[str]:
    completion_id = new_completion_id()
    yield chunk(completion_id, req.model, {"role": "assistant", "content": ""})

    finish = "stop"
    try:
        async for event in agent.run(req.messages, ctx):
            if event.kind == "content":
                yield chunk(completion_id, req.model, {"content": event.text})
            elif event.kind == "status":
                yield chunk(completion_id, req.model, {"content": _render_status(event.text)})
            elif event.kind == "error":
                yield chunk(completion_id, req.model, {"content": f"\n\n**Error:** {event.text}"})
                finish = "stop"
    except Exception:  # noqa: BLE001 - the stream is already open; report in-band
        log.exception("agent %s failed mid-stream", req.model)
        yield chunk(
            completion_id,
            req.model,
            {"content": "\n\n**Error:** the agent failed unexpectedly."},
        )

    yield chunk(completion_id, req.model, {}, finish=finish)
    yield DONE
