# ZINO architecture

ZINO is a personal agentic platform. Open WebUI provides the entire application
— chat, accounts, history, RAG, file handling, and agent authoring. ZINO
provides the infrastructure that runs it on GCP, and the decisions about how.

**This repo contains no application code.** That is deliberate (ADR 0001).

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
                    └──┬────────────────┬──┘
                       │                │  ADC
          ┌────────────▼───┐   ┌────────▼─────┐
          │  Cloud SQL     │   │  GCS bucket  │
          │  Postgres 16   │   │  uploads     │
          │  + pgvector    │   │              │
          └────────────────┘   └──────────────┘
                       │
                       │  model providers, agents, tools, knowledge
                       │  all stored here, configured in the admin UI
                       ▼
            (out to whichever LLM APIs you connect)

   Firebase Auth ──── OIDC ────▶ zino-webui   (opt-in; off by default)
```

## Where configuration lives

This is the one thing to internalise about ZINO.

| Configured in | What | Why |
|---------------|------|-----|
| **Admin UI** → database | Model providers and keys, agents, tools, knowledge, permissions | `ENABLE_PERSISTENT_CONFIG` is true, so database values override env on boot |
| **Terraform** → env | Database, storage, OIDC login, pinned version | Infrastructure; must be reproducible from git |

Setting a model connection in env would seed only the first boot and then be
silently overridden — config that looks authoritative but is not. So ZINO sets
none of them. Full detail in [configuring.md](configuring.md).

## Components

| Path | What it is |
|------|------------|
| `scripts/` | CLI bootstrap, deploy, enable-oidc and destroy |
| `infra/terraform/` | The entire GCP footprint |
| `infra/firebase/` | Hosting and Auth notes; `firebase.json` is at the repo root |
| `compose.yaml` | Local stack mirroring the production topology |
| `docs/adr/` | Why things are the way they are |
| `docs/upgrading.md` | Taking a new upstream release |

## State, and why none of it is on disk

Cloud Run's filesystem is ephemeral and the instance can be replaced at any
time. Anything Open WebUI would write locally is redirected:

| Would be local | Actually |
|----------------|----------|
| `webui.db` (SQLite) | Cloud SQL Postgres, via `DATABASE_URL` |
| Chroma vector store | pgvector in the same instance |
| `uploads/` | GCS bucket, via `STORAGE_PROVIDER=gcs` |

A consequence worth stating plainly: **the database is the platform.** Your
agents, tools and provider keys are rows in it, not files in git. Cloud SQL is
configured with daily backups and 7-day point-in-time recovery.

## Known limits

These are real and deliberate, not oversights:

- **`zino-webui` is capped at one instance.** Open WebUI holds websockets for
  chat streaming; fanning those out across instances needs Redis
  (`WEBSOCKET_MANAGER=redis`). Until that exists, more than one instance would
  drop streams. One instance is correct for a personal platform.
- **That instance stays warm**, which is the platform's cost floor. Scaling to
  zero would drop live streams and add a slow cold start to every first message.
  This is the single biggest line on the bill.
- **Secrets depend on `WEBUI_SECRET_KEY`.** Provider API keys are encrypted with
  it. Rotating it invalidates all of them.
- **Login is email/password until you opt in.** Firebase Auth needs an OAuth
  client, and creating one is console-only, so it is not part of the default
  path. `scripts/enable-oidc.sh` switches it on.
- **Terraform has not been applied yet.** It is formatted and internally
  consistent, but no `plan` has run against a real project. The deploy scripts
  were exercised against stubbed `gcloud`/`terraform` binaries — control flow
  and idempotency are verified, cloud-side command syntax is not.
