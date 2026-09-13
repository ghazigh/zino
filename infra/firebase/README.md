# Firebase layer

Firebase does two jobs for ZINO, and only one of them is set up by default.

## 1. Hosting — edge, domain and TLS (automatic)

`firebase.json` at the repo root rewrites every path to the `zino-webui` Cloud
Run service, giving us a managed certificate, a CDN edge and a custom domain
without standing up a load balancer.

`scripts/deploy.sh` publishes this. Nothing here needs doing by hand.

`public/` is intentionally empty: there are no static assets, because the
rewrite catches `**`. Firebase requires the directory to exist.

> **Region.** The `region` in `firebase.json` must match `var.region` in
> Terraform. It is hardcoded because `firebase.json` is not templated —
> `scripts/bootstrap.sh` warns if the two disagree.

## 2. Authentication — identity (opt-in)

**ZINO does not use Firebase Auth by default.** Open WebUI's own
email/password accounts work out of the box and need no configuration, which
keeps the first deploy entirely scriptable.

Turn on Google sign-in later with:

```sh
./scripts/enable-oidc.sh
```

That script does everything that can be done from a terminal — creating the
secrets, storing the credentials, flipping `enable_oidc` — and tells you the
two things that must be clicked.

### Why two steps cannot be scripted

This is a real gap in the tooling, not an oversight:

- **The Firebase CLI cannot configure sign-in providers.** Its entire auth
  surface is `auth:export` and `auth:import` — moving user records, not
  settings.
- **gcloud cannot create a generic OAuth 2.0 client.** `gcloud alpha iap
  oauth-clients` exists, but only for Identity-Aware Proxy brands, which is a
  different product path.

So enabling the Google provider and copying its client credentials are console
actions. Everything downstream of them is scripted.

### What the script asks you to click

1. **Enable the Google provider** —
   `console.firebase.google.com/project/<project>/authentication/providers`
2. **Add the redirect URI** to the OAuth client that step 1 created, at
   `console.cloud.google.com/apis/credentials`:
   `https://<your-domain>/oauth/oidc/callback`

Existing email/password accounts survive the switch:
`OAUTH_MERGE_ACCOUNTS_BY_EMAIL` is on, so signing in with Google on the same
address adopts the existing account rather than creating a duplicate.

## What Firebase is deliberately *not* used for

- **Firestore** — ZINO's state is relational and already lives in Cloud SQL.
  Adding Firestore would split the source of truth for no gain.
- **Cloud Functions** — ZINO deploys no code of its own. Agents and tools are
  authored inside Open WebUI and stored in its database
  (`docs/configuring.md`), so there is nothing for a function to run.
