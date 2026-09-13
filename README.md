# ZINO

A personal agentic platform, built on [Open WebUI](https://github.com/open-webui/open-webui)
and hosted on GCP + Firebase.

Open WebUI supplies the chat product: the interface, accounts, history, RAG and
file handling. ZINO supplies the agents — and the infrastructure that runs the
whole thing.

---

## How it fits together

Open WebUI runs as the **unmodified upstream image**, pinned to `v0.9.6`. ZINO
is everything around it, and plugs in through the OpenAI API shape: the agent
gateway serves `/v1/models` and `/v1/chat/completions`, so each ZINO agent shows
up in Open WebUI's model picker like any other model.

That seam is the point. Upgrading upstream is a version bump, not a merge.
See [ADR 0001](docs/adr/0001-base-strategy.md) for why, and
[docs/architecture.md](docs/architecture.md) for the full picture.

```
browser → Firebase Hosting → Cloud Run: zino-webui (Open WebUI)
                                   ├→ Cloud Run: zino-agents (this repo)
                                   ├→ Cloud SQL Postgres + pgvector
                                   └→ GCS bucket
```

## Run it locally

Requires Docker and [uv](https://docs.astral.sh/uv/).

```sh
make setup          # creates .env, installs dev dependencies
make secrets        # prints generated values — paste them into .env
make up             # starts Open WebUI, Postgres+pgvector, and the gateway
```

ZINO is then at <http://localhost:3000>. The first account you register becomes
the administrator.

Pick the **ZINO Echo** model to confirm the wiring end to end — it needs no API
key and streams your message back. For **ZINO Assistant**, set
`ZINO_UPSTREAM_API_KEY` in `.env` first.

```sh
make test           # 30 tests
make lint
make dev            # gateway alone, with reload, no Docker
make help           # everything else
```

## Deploy it

```sh
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # set project_id
terraform init && terraform apply
```

Then the parts Terraform deliberately does not hold the values for:

```sh
# The model provider key the agents call.
echo -n "sk-..." | gcloud secrets versions add zino-upstream-api-key --data-file=-
```

Set the three GitHub Actions repository variables from the Terraform outputs —
`GCP_PROJECT_ID`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_DEPLOYER_SA` — and
pushes to `main` deploy themselves. CI authenticates with Workload Identity
Federation, so no service-account key is ever created or stored.

Firebase Hosting and Firebase Auth need a few console steps:
[infra/firebase/README.md](infra/firebase/README.md).

## Extending it

**An agent** is a class with an async `run()` that yields events. Add a file
under `services/zino-agents/zino_agents/agents/`, register it, and it is in the
model picker.

**A tool** is an async function with a JSON schema, registered with a decorator.
`ZINO Assistant` picks it up automatically — it sends every registered tool to
the model and runs a tool-calling loop over the results.

Both are walked through in [docs/architecture.md](docs/architecture.md).

## Repository map

| Path | |
|------|--|
| `services/zino-agents/` | Agent gateway: agents, tools, OpenAI-compatible API |
| `infra/terraform/` | The GCP footprint |
| `infra/firebase/` | Hosting + Auth setup |
| `compose.yaml` | Local stack, mirrors production |
| `docs/adr/` | Decisions, and why |
| `docs/upgrading.md` | Taking a new Open WebUI release |

## Status

Foundation. The platform runs locally and the infrastructure is defined, with
two agents (`zino-echo`, `zino-assistant`) and two tools (`current_time`,
`calculator`) as working reference implementations.

The Terraform and the workflows have not yet been run against a real GCP
project — `terraform validate` and a first `apply` are the next step.
