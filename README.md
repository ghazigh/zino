# ZINO

A personal agentic platform: [Open WebUI](https://github.com/open-webui/open-webui)
running on GCP + Firebase.

Open WebUI is the whole application — chat, accounts, history, RAG, file
handling, and agent authoring. This repo is the infrastructure that runs it, and
the record of why it is built this way.

**There is no application code here, on purpose.** ZINO runs the upstream image
unmodified, pinned to `v0.9.6`. Upgrading is a version bump, not a merge.
See [ADR 0001](docs/adr/0001-base-strategy.md).

```
browser → Firebase Hosting → Cloud Run: zino-webui (Open WebUI)
                                   ├→ Cloud SQL Postgres + pgvector
                                   └→ GCS bucket
```

## Run it locally

Requires Docker.

```sh
make setup      # creates .env
make secrets    # prints a generated WEBUI_SECRET_KEY — paste it into .env
make up         # starts Open WebUI + Postgres/pgvector
```

ZINO is then at <http://localhost:3000>. The first account you register becomes
the administrator.

## Connect a model, build an agent

Both happen **in the app**, not in this repo:

- **Admin Panel → Settings → Connections** — add an OpenAI-compatible provider
  and its API key.
- **Workspace → Models** — create an agent: system prompt, knowledge, tools.

Open WebUI stores all of it in its database, so it survives restarts and
redeploys. This is deliberate, and [docs/configuring.md](docs/configuring.md)
explains the one rule that follows from it: settings changed in the UI override
environment variables, so ZINO sets no model config in Terraform at all.

## Deploy it

**From a browser, with nothing installed:** use Cloud Shell —
[docs/deploy-from-browser.md](docs/deploy-from-browser.md).

**From your own machine:** two commands.

```sh
gcloud auth login && gcloud auth application-default login

./scripts/bootstrap.sh --project zino-prod --billing $(gcloud beta billing accounts list --format='value(ACCOUNT_ID)' | head -1)
./scripts/deploy.sh
```

`bootstrap.sh` creates the project, links billing, enables the APIs, creates the
versioned bucket for Terraform state, and writes the Terraform config. It is
idempotent — re-running it changes nothing.

`deploy.sh` shows you a plan, asks before applying, waits for the app to answer,
then publishes Firebase Hosting and prints your URL. Use `--plan-only` to look
first.

Login works immediately with Open WebUI's own accounts. To switch to Google
sign-in later:

```sh
./scripts/enable-oidc.sh    # scripts everything except two console clicks
```

That is the one part that cannot be fully automated — neither gcloud nor the
Firebase CLI can create an OAuth client or enable a sign-in provider. The script
does the rest and tells you exactly what to click.

To tear it all down: `./scripts/destroy.sh`.

## Repository map

| Path | |
|------|--|
| `scripts/` | Bootstrap, deploy, enable-oidc, destroy |
| `infra/terraform/` | The GCP footprint |
| `infra/firebase/` | Hosting + Auth setup |
| `compose.yaml` | Local stack, mirrors production |
| `docs/configuring.md` | Where config lives, and why |
| `docs/architecture.md` | How it fits together |
| `docs/adr/` | Decisions, and why |
| `docs/cost.md` | What it costs, and the levers |
| `docs/deploy-from-browser.md` | Deploying from Cloud Shell, no local installs |
| `docs/upgrading.md` | Taking a new Open WebUI release |

## Status

Infrastructure and the deploy scripts are written; the local stack runs.

**Not yet deployed.** Terraform has never been applied against a real GCP
project, and the scripts' `gcloud` calls were tested against stubs rather than
against Google — the control flow, idempotency and generated files are verified,
the cloud-side command syntax is not. Expect the first `bootstrap.sh` run to
need a fix or two.

Known limits are in [docs/architecture.md](docs/architecture.md#known-limits),
and [docs/cost.md](docs/cost.md) has the money. Configured to scale to zero:
roughly $10-25/month, mostly the database, with a ~30-60s cold start on the
first request after a quiet spell.
