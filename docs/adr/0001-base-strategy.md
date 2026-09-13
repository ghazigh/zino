# ADR 0001 — Build ZINO as a deployment of a pinned Open WebUI

- **Status:** Accepted
- **Date:** 2026-09-13
- **Amended:** 2026-09-13 — agent gateway removed; see *Amendment* below.

## Context

ZINO is a personal agentic platform built "based on Open WebUI". There are three
ways to depend on an upstream project of this shape (SvelteKit frontend +
FastAPI backend, shipped as a single container image):

1. **Fork the source.** Vendor all of `open-webui/open-webui` into this repo and
   patch it directly.
2. **Run it unmodified.** Deploy the upstream image at a pinned version and add
   capability through its supported extension points.
3. **Hybrid.** Maintain a patch series applied to a pinned upstream checkout at
   build time.

The hosting target is **GCP Cloud Run fronted by Firebase Hosting** (ADR 0002).
That constraint is decisive: Cloud Run deploys a container image. With option 1
or 3, every upstream release means rebuilding the SvelteKit frontend and the
Python backend in CI and re-resolving merge or patch conflicts before we can
ship. Open WebUI releases frequently — it moved through v0.8.x to v0.9.6 over a
short window.

## Decision

Use **option 2**. Open WebUI runs as the unmodified upstream image at a pinned
tag. This repo contains no application code at all — it is the infrastructure
and the operational knowledge:

- `infra/` — the GCP and Firebase topology as code.
- `docs/` — how it fits together and how to change it.
- `compose.yaml` — a local stack mirroring production.

Upgrades become a version bump in two declared places, not a merge.

## Amendment

The original version of this ADR also added an **agent gateway** — a small
FastAPI service exposing custom agents to Open WebUI over the OpenAI API shape.
It was removed before first deploy.

The reason: Open WebUI already provides agent authoring in the product. Models,
system prompts, knowledge bases and Python tools are all created in the admin UI
and stored in its database (`docs/configuring.md`). A separate gateway would
have been a second, weaker place to do the same job — one that needed its own
deploys, its own tests and its own credentials to say something the UI already
says better.

The seam it used is still there and still supported: anything OpenAI-compatible
can be added under **Admin Panel → Settings → Connections**. If ZINO ever needs
an agent that genuinely cannot be expressed in the UI, it can be added back as a
service behind that same connection, without changing anything else.

The general principle, worth keeping: **prefer the product's own extension point
over new code**. Code we do not write cannot break on upgrade.

## Consequences

**We get:** cheap upgrades, a repo small enough to read in one sitting, no build
step and no image registry, and agents that are editable in a browser rather
than through a deploy.

**We give up:** the ability to change Open WebUI's own UI code. Branding is
limited to what upstream exposes (`WEBUI_NAME`, custom CSS, static asset
overrides). If ZINO ever needs a UI change upstream will not accept, revisit
this ADR and move to option 3.

**The trade to watch:** configuration now lives in the database rather than in
git. That is the price of using the product's own extension points, and it makes
database backups the thing that protects your work. See `docs/configuring.md`.
