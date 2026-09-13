# Configuring ZINO

Everything about models and agents is configured **in the running app**, not in
this repo. This page explains where the line sits and why.

## The rule

| Configured in | What |
|---------------|------|
| **The admin UI** | Model providers, API keys, agents, tools, knowledge bases, user permissions |
| **Terraform / env** | Database, storage, login/OIDC, the pinned upstream version |

The reason is `ENABLE_PERSISTENT_CONFIG`, which defaults to **true** upstream.
Open WebUI writes settings changed in the UI to its own database, and on the
next boot those database values **take precedence over environment variables**.

So an env var for a model connection would seed the very first boot and then be
silently overridden the moment you touch that screen — config that looks
authoritative but is not. That is why ZINO deliberately sets none of them.

The exception is OAuth: `ENABLE_OAUTH_PERSISTENT_CONFIG` defaults to **false**,
so login settings stay env-driven on every boot. Login config lives in
Terraform, where it belongs.

Login itself is off-by-default in the sense that ZINO ships with Open WebUI's
own email/password accounts and no OIDC. Run `./scripts/enable-oidc.sh` to
switch to Google sign-in; `infra/firebase/README.md` explains why that one is
not fully scriptable.

## Connecting a model provider

**Admin Panel → Settings → Connections.**

Add an OpenAI-compatible connection with the provider's base URL and your API
key. This covers most providers:

| Provider | Base URL |
|----------|----------|
| OpenAI | `https://api.openai.com/v1` |
| Anthropic | via an OpenAI-compatible proxy, or the Anthropic function/pipe |
| Google Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` |
| Groq | `https://api.groq.com/openai/v1` |
| OpenRouter | `https://openrouter.ai/api/v1` |
| A local Ollama | enable the Ollama connection instead |

Keys are stored in the database, encrypted with `WEBUI_SECRET_KEY`. Two things
follow from that:

- **Never lose `WEBUI_SECRET_KEY`.** Rotating it makes every stored key
  unreadable and you will have to re-enter them. It is in Secret Manager as
  `zino-webui-secret-key`.
- Keys are **not** in Terraform state or in this repo, which is where you want
  them not to be.

## Building an agent

**Workspace → Models → +**

An agent in Open WebUI is a saved configuration on top of a base model:

- a **system prompt** — the agent's instructions,
- **knowledge** — collections it can retrieve from (this is the RAG layer,
  backed by pgvector),
- **tools** — what it is allowed to call,
- parameters like temperature, and who it is shared with.

It then appears in the model picker like any other model.

For tools beyond the built-ins, **Workspace → Tools** takes Python directly, and
**Admin Panel → Functions** handles pipes and filters if you need to intercept
requests. Both are edited in the browser and stored in the database — nothing to
deploy.

## What this means for backups

Because all of it lives in Postgres, your agents, tools and provider keys are
only as safe as your database backups. Cloud SQL is configured with daily
backups and 7-day point-in-time recovery in `infra/terraform/sql.tf`.

Worth knowing: if you build something substantial in **Workspace → Tools**, it
exists only in that database. Export anything you would be upset to lose.
