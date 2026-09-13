# ADR 0001 — Build ZINO as an extension layer on a pinned Open WebUI

- **Status:** Accepted
- **Date:** 2026-09-13

## Context

ZINO is a personal agentic platform built "based on Open WebUI". There are three
ways to depend on an upstream project of this shape (SvelteKit frontend +
FastAPI backend, shipped as a single container image):

1. **Fork the source.** Vendor all of `open-webui/open-webui` into this repo and
   patch it directly.
2. **Extension layer.** Run the upstream image unmodified at a pinned version and
   add capability through its supported extension points.
3. **Hybrid.** Maintain a patch series applied to a pinned upstream checkout at
   build time.

The hosting target is **GCP Cloud Run fronted by Firebase Hosting** (see ADR
0002). That constraint is decisive: Cloud Run deploys a container image. With
option 1 or 3, every upstream release means rebuilding the SvelteKit frontend
and the Python backend in CI and re-resolving merge or patch conflicts before we
can ship. Open WebUI releases frequently — it moved through v0.8.x to v0.9.6
over a short window.

## Decision

Use **option 2**. Open WebUI runs as the unmodified upstream image at a pinned
tag. ZINO is everything around it:

- `services/zino-agents` — an OpenAI-compatible agent gateway that Open WebUI
  consumes as just another model provider.
- `infra/` — the GCP and Firebase topology as code.
- `config/` — declarative Open WebUI configuration.

Upstream upgrades become a version bump in one place
(`ZINO_OPENWEBUI_VERSION`), not a merge.

## Consequences

**We get:** cheap upgrades, a small reviewable repo, no build step for the
frontend, and a clean security boundary — our code is a separate Cloud Run
service with its own service account.

**We give up:** the ability to change Open WebUI's own UI code. Branding is
limited to what upstream exposes (`WEBUI_NAME`, custom CSS, static asset
overrides). If ZINO ever needs a UI change upstream will not accept, revisit
this ADR and move to option 3 — the extension layer stays valid either way,
so that migration is additive rather than a rewrite.

**Integration contract:** ZINO talks to Open WebUI through the OpenAI API shape
(`/v1/models`, `/v1/chat/completions`). That is a stable, documented surface and
is what keeps this decision reversible.
