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

```sh
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # set project_id
terraform init && terraform apply
```

Then the Firebase console steps for Hosting and Auth:
[infra/firebase/README.md](infra/firebase/README.md).

CI authenticates with Workload Identity Federation, so no service-account key is
ever created or stored.

## Repository map

| Path | |
|------|--|
| `infra/terraform/` | The GCP footprint |
| `infra/firebase/` | Hosting + Auth setup |
| `compose.yaml` | Local stack, mirrors production |
| `docs/configuring.md` | Where config lives, and why |
| `docs/architecture.md` | How it fits together |
| `docs/adr/` | Decisions, and why |
| `docs/upgrading.md` | Taking a new Open WebUI release |

## Status

Infrastructure is defined and internally consistent; the local stack runs.

**Not yet deployed.** Terraform has never been applied against a real GCP
project — `terraform plan` is the next step, and the first run should be
expected to surface errors. Known limits are in
[docs/architecture.md](docs/architecture.md#known-limits); the one to read first
is that a always-warm Cloud Run instance sets a monthly cost floor.
