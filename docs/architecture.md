# ZINO architecture

ZINO is a personal agentic platform. Open WebUI provides the chat product — UI,
accounts, conversation history, RAG, file handling. ZINO provides the agents,
and the infrastructure that makes the whole thing run on GCP.

## Shape

```
                    ┌──────────────────────┐
   browser ────────▶│  Firebase Hosting    │  TLS, custom domain, CDN edge
                    │  rewrite ** → Run    │
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │  Cloud Run           │
                    │  zino-webui          │  upstream image, unmodified
                    │  (Open WebUI v0.9.6) │
                    └──┬────────┬───────┬──┘
                       │        │       │
        Bearer ZINO_API_KEY     │       │  ADC
                       │        │       │
        ┌──────────────▼──┐  ┌──▼───────▼────┐  ┌──────────────┐
        │  Cloud Run      │  │  Cloud SQL    │  │  GCS bucket  │
        │  zino-agents    │  │  Postgres 16  │  │  uploads     │
        │  (this repo)    │  │  + pgvector   │  │              │
        └────────┬────────┘  └───────────────┘  └──────────────┘
                 │
                 ▼
        model provider (OpenAI-compatible)

   Firebase Auth ──── OIDC ────▶ zino-webui
```

## The integration seam

ZINO's agents reach Open WebUI through **the OpenAI API shape**, nothing else.
The gateway serves `/v1/models` and `/v1/chat/completions`; Open WebUI is
configured with `OPENAI_API_BASE_URLS` pointing at it. Each ZINO agent appears
as a model in the picker (`zino-echo`, `zino-assistant`).

This is the whole reason ADR 0001 works. It is a stable, documented, widely
implemented contract, so upstream can change its internals freely without
breaking ZINO, and ZINO's agents can be tested with `curl` and consumed by any
other OpenAI-compatible client.

The one thing the plain OpenAI protocol lacks is a progress channel. A
multi-step agent is otherwise silent while it calls tools, so the gateway
renders `status` events as italic lines in the message stream — visible
progress, no protocol extension.

## Components

| Path | What it is |
|------|------------|
| `services/zino-agents/` | The agent gateway. FastAPI, OpenAI-compatible, streams SSE. |
| `services/zino-agents/zino_agents/agents/` | Agent implementations. Add one file per agent. |
| `services/zino-agents/zino_agents/tools/` | Tools, described by JSON schema and registered at import. |
| `infra/terraform/` | The entire GCP footprint. |
| `infra/firebase/` | Hosting and Auth notes; `firebase.json` lives at the repo root. |
| `compose.yaml` | Local stack mirroring the production topology. |
| `docs/adr/` | Why things are the way they are. |

## Adding an agent

1. Subclass `Agent` in `zino_agents/agents/`, set `id`/`name`/`description`,
   implement `run()` as an async generator yielding `AgentEvent`s.
2. Register it in `zino_agents/registry.py`.
3. It appears in Open WebUI's model picker on next restart.

## Adding a tool

Decorate an async function with `@registry.tool(...)` in
`zino_agents/tools/`, and import the module from `registry.py` so registration
happens. The JSON schema you pass is what the model sees — write the
description for the model.

Tools must never raise into the agent loop. `_execute_tool` converts exceptions
into text the model can read and recover from; a tool that hard-fails would end
the whole run instead of one step of it.

## State, and why none of it is on disk

Cloud Run's filesystem is ephemeral. Anything Open WebUI would write locally is
redirected:

| Would be local | Actually |
|----------------|----------|
| `webui.db` (SQLite) | Cloud SQL Postgres, via `DATABASE_URL` |
| Chroma vector store | pgvector in the same instance |
| `uploads/` | GCS bucket, via `STORAGE_PROVIDER=gcs` |

## Known limits

These are real and deliberate, not oversights:

- **`zino-webui` is capped at one instance.** Open WebUI holds websockets for
  chat streaming; fanning those out across instances needs Redis
  (`WEBSOCKET_MANAGER=redis`). Until that exists, more than one instance would
  drop streams. One instance is correct for a personal platform.
- **That instance stays warm**, which is the platform's cost floor. Scaling to
  zero would drop live streams and add a slow cold start to every first message.
- **The agent gateway is publicly addressable**, guarded by a bearer token
  rather than Cloud Run IAM, because Open WebUI cannot mint Google ID tokens.
  The token is compared in constant time and the gateway refuses to serve
  production traffic if it is unset. See the comment on `ingress` in
  `infra/terraform/cloudrun.tf` for how to close this off with Direct VPC egress.
- **The agent gateway is stateless.** Conversation history belongs to Open WebUI
  and arrives with each request. Agents that need memory of their own will need
  a store adding.
