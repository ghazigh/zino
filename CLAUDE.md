# ZINO — working notes

Personal agentic platform: upstream Open WebUI on GCP + Firebase. This repo is
infrastructure only, no application code (see `docs/adr/0001-base-strategy.md`).

The user deploys from **Cloud Shell**, not a local machine.
Project: `zino-508515`. Region: `europe-west1`.

## Known gotchas — tell the user the fix when these appear

### Terraform says credentials are missing / expired

Cloud Shell writes Application Default Credentials under `/tmp`, which is
cleared between sessions. The cloned repo in `$HOME` persists, so it looks like
nothing changed — but Terraform has lost its login.

**Fix:** re-run, and answer `y` to both prompts.

```sh
gcloud auth application-default login
```

Notes for explaining it:
- gcloud says *"it is not necessary to use this command"*. That is true for
  gcloud, false for Terraform, which reads a separate credential set.
- It may offer to enable `cloudresourcemanager.googleapis.com`. That is free and
  expected.
- The verification code pasted back is a one-time key to the account. It should
  never be pasted anywhere except that prompt.

### A script appears to hang with no output

Almost always `gcloud` asking a question that cannot be seen, because the call
sends stderr to `/dev/null`. The classic case is querying a resource whose API
is not enabled: gcloud stops to ask *"enable and retry? (y/N)"*.

**Fix:** Ctrl+C, then add `--quiet` to that call, or guard it behind
`gcloud services list --enabled`. Both patterns are already in
`scripts/bootstrap.sh` — follow them for any new gcloud call.

### Terraform "runs" but nothing happens

Cloud Shell ships a Terraform *placeholder* on PATH: it prints install
instructions and exits 0. `command -v terraform` finds it and `terraform init`
looks like it succeeded while doing nothing.

**Fix:** `./scripts/install-terraform.sh && export PATH="$HOME/bin:$PATH"`

`require_terraform` in `scripts/lib.sh` now catches this by checking the output
starts with `Terraform v`. Presence on PATH is never sufficient proof a tool
works — prefer asking a tool to identify itself.

### Cloud Shell disconnects mid-deploy

It idles out after ~20 minutes and `terraform apply` on Cloud SQL is slow.
**Fix:** re-run `./scripts/deploy.sh`. Terraform picks up where it stopped.

## Communication

The user prefers **brief, plain-language, step-by-step** answers — short
sentences, no jargon, numbered steps they can paste. Explain what a thing does
before why it matters. They are not a cloud engineer; do not assume GCP
vocabulary.

Always say plainly whether a step **costs money** before they run it.

## Conventions

- Never put model provider keys or agent config in Terraform or env. Open WebUI
  persists those in its database and they override env on boot — see
  `docs/configuring.md`. That split is deliberate.
- Every `gcloud` call in `scripts/` takes `--quiet` and must not prompt.
- Scripts are idempotent; verify both the first-run and re-run paths.
- `shellcheck -x scripts/*.sh` and `terraform fmt -check` must pass; CI enforces.
- Verify config keys against the pinned upstream source rather than from memory
  (`docs/upgrading.md` explains how).

## Environment limits when working on this repo

Terraform providers cannot be downloaded (`registry.terraform.io` is blocked),
and gcloud cannot be installed (`dl.google.com` blocked). So:
- `terraform validate` is not available — only `fmt` and reference checking.
- Script changes are verified by stubbing `gcloud`/`terraform`/`npx` on `PATH`.
  Keep doing that; it has caught real bugs.
