# ZINO — working notes

Personal agentic platform: upstream Open WebUI on GCP + Firebase. This repo is
infrastructure only, no application code (see `docs/adr/0001-base-strategy.md`).

The user deploys from **Cloud Shell**, not a local machine.
Project: `zino-508515`. Region: `europe-west1`.

## Known gotchas — tell the user the fix when these appear

### Terraform: "invalid token JSON from metadata"

**Re-running `gcloud auth application-default login` does NOT fix this.** That
was the first guess and it is wrong — worth stating plainly, because the error
looks exactly like an expired login.

Terraform's Google library does not honour `CLOUDSDK_CONFIG`. Its chain is
`GOOGLE_APPLICATION_CREDENTIALS`, then `~/.config/gcloud/`, then the GCE
metadata server. Cloud Shell relocates gcloud's config dir into `/tmp`, so the
file the login writes is not where Terraform looks; it falls through to the
metadata server and fails there. Logging in again just rewrites the same
ignored file.

**Fix:** `require_adc` in `scripts/lib.sh` locates the file and exports
`GOOGLE_APPLICATION_CREDENTIALS`. By hand it is:

```sh
export GOOGLE_APPLICATION_CREDENTIALS="$CLOUDSDK_CONFIG/application_default_credentials.json"
```

The general lesson: when a tool reports a credential error, check *which*
credential source it actually reached before assuming the credential is stale.
"from metadata" in that message was the whole clue.

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

### Cloud SQL is public-IP with no authorised networks

Deliberate, not an oversight. Cloud Run's Cloud SQL socket connector cannot
route to a private-IP-only instance unless the service also has Direct VPC
egress. With private IP and no VPC egress, `terraform apply` succeeds and the
app then cannot reach its database — a plan cannot catch this, because nothing
is syntactically wrong.

If tightening this later: add `vpc_access` with Direct VPC egress to the Cloud
Run service *first*, then flip `ipv4_enabled` to false.

### Cloud SQL edition must be pinned

Cloud SQL defaults new Postgres instances to ENTERPRISE_PLUS, which rejects
shared-core tiers. `edition = "ENTERPRISE"` in `sql.tf` is what makes
db-f1-micro legal. If the tier ever changes, check it against the edition.

### iam.googleapis.com vs iamcredentials.googleapis.com

Different services, easily confused. `iam` creates service accounts and
workload identity pools; `iamcredentials` mints short-lived tokens. Both are
needed. Enabling only the second broke the first apply.

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
