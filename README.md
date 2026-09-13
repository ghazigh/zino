# ZINO

A personal agentic platform: [Open WebUI](https://github.com/open-webui/open-webui)
with your own models, agents and knowledge.

Open WebUI is the whole application — chat, accounts, history, RAG, file
handling, and agent authoring. This repo runs it, pinned to `v0.9.6`, and holds
the decisions about how.

**There is no application code here, on purpose.** ZINO runs the upstream image
unmodified, so upgrading is a version bump rather than a merge.
See [ADR 0001](docs/adr/0001-base-strategy.md).

---

## Run it

Needs [Docker](https://docs.docker.com/get-started/get-docker/). Nothing else,
no account, no cost.

```sh
git clone https://github.com/ghazigh/zino
cd zino
./scripts/start.sh
```

That generates your secret key, starts Open WebUI and its database, waits for
it, and prints the address. First run pulls about 2GB.

Then open <http://localhost:3000> and register — **the first account becomes the
administrator**.

```sh
./scripts/start.sh --stop    # stop, keeping all your data
./scripts/start.sh --logs    # see what it is doing
```

## Connect a model, build an agent

Both happen **in the app**, not in this repo:

- **Admin Panel → Settings → Connections** — add an OpenAI-compatible provider
  and its API key.
- **Workspace → Models** — create an agent: system prompt, knowledge, tools.

Open WebUI stores all of it in its database, so it survives restarts.
[docs/configuring.md](docs/configuring.md) explains the one rule that follows:
settings changed in the UI override environment variables, so ZINO deliberately
sets no model config anywhere in this repo.

> **Keep your `.env`.** The key in it encrypts the provider API keys you enter
> in the admin UI. Lose it and you re-enter them all.

## What you get locally

Everything, with one difference from a server deployment: it is reachable only
from your machine. Chat, agents, tools, file uploads, and RAG over your own
documents (Postgres with pgvector, same as the cloud setup would use) all work.

Your data lives in Docker volumes and persists across restarts.

## Deploying it to the internet — optional

`infra/` holds a complete GCP + Firebase deployment: Cloud Run, Cloud SQL with
pgvector, GCS, Firebase Hosting, and CI through Workload Identity Federation.

**It is unfinished.** It reaches `terraform apply` and creates most resources,
but has not been driven to a working deployment end to end. Treat it as a
strong starting point rather than a working path, and read
[docs/cost.md](docs/cost.md) first — expect roughly $10–25/month.

Start with [docs/deploy-from-browser.md](docs/deploy-from-browser.md).

## Repository map

| Path | |
|------|--|
| `compose.yaml` | The local stack |
| `scripts/start.sh` | Start, stop, logs |
| `docs/configuring.md` | Where config lives, and why |
| `docs/architecture.md` | How it fits together |
| `docs/adr/` | Decisions, and why |
| `docs/upgrading.md` | Taking a new Open WebUI release |
| `infra/` | The optional cloud deployment |
