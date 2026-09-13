# ADR 0002 — GCP + Firebase hosting topology

- **Status:** Accepted
- **Date:** 2026-09-13

## Context

ZINO is hosted on GCP with Firebase. Open WebUI expects a writable data
directory, a database, and a vector store. A naive lift onto Cloud Run breaks:
Cloud Run's filesystem is ephemeral and instances scale to zero, so the default
SQLite database and local Chroma vector store would lose data.

## Decision

Externalise every piece of state, using the providers Open WebUI already
supports natively (verified against v0.9.6 `backend/open_webui/config.py`):

| Concern        | Choice                        | Upstream config |
|----------------|-------------------------------|-----------------|
| Relational DB  | Cloud SQL for PostgreSQL      | `DATABASE_URL` |
| Vector store   | pgvector, same Cloud SQL instance | `VECTOR_DB=pgvector`, `PGVECTOR_DB_URL` |
| File storage   | Cloud Storage bucket          | `STORAGE_PROVIDER=gcs`, `GCS_BUCKET_NAME` |
| Identity       | Firebase Auth (OIDC)          | `OPENID_PROVIDER_URL`, `OAUTH_CLIENT_ID` |
| Secrets        | Secret Manager                | mounted as env at deploy |
| Edge / domain  | Firebase Hosting → Cloud Run  | rewrite in `firebase.json` |

Reusing the single Cloud SQL instance for both the app database and pgvector
avoids a second stateful service; Open WebUI defaults `PGVECTOR_DB_URL` to
`DATABASE_URL` for exactly this case.

Two Cloud Run services, not one:

- `zino-webui` — the upstream Open WebUI image.
- `zino-agents` — ZINO's own agent gateway.

They are deployed independently, scale independently, and hold different IAM
service accounts, so a bug in an agent tool cannot reach the WebUI's database
credentials.

## Consequences

- Cloud Run must keep **at least one warm instance** for `zino-webui`. Open WebUI
  holds websocket connections for chat streaming; scaling to zero drops them.
  This is a real cost floor (see `docs/architecture.md`).
- Multi-instance requires Redis for websocket fan-out (`WEBSOCKET_MANAGER=redis`).
  Until then `zino-webui` is pinned to `max_instances = 1`, which is correct for
  a personal platform and is called out in Terraform.
- GCS credentials: Cloud Run supplies the runtime service account automatically,
  so `GOOGLE_APPLICATION_CREDENTIALS_JSON` is left unset in production and the
  bucket is reached via Application Default Credentials.
- CI authenticates with **Workload Identity Federation**, not a downloaded
  service-account key. No long-lived credential exists to leak.
