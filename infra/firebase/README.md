# Firebase layer

Firebase does two jobs for ZINO. Neither of them is serving the app itself —
that is Cloud Run.

## 1. Hosting — edge, domain and TLS

`firebase.json` at the repo root rewrites every path to the `zino-webui` Cloud
Run service. Firebase gives us a managed certificate, a CDN edge, and a custom
domain without standing up a load balancer.

```sh
firebase use --add          # select the GCP project, alias it "prod"
firebase deploy --only hosting
```

`public/` is intentionally empty: there are no static assets to serve, because
the rewrite catches `**`. Firebase requires the directory to exist.

> **Region.** The `region` in `firebase.json` must match `var.region` in
> Terraform. It is hardcoded because `firebase.json` is not templated — if you
> change the Terraform region, change it here too.

## 2. Authentication — identity

Firebase Auth is the OIDC provider for Open WebUI. Terraform wires the
Cloud Run side (`OPENID_PROVIDER_URL`, `OPENID_REDIRECT_URI`); the parts that
have to be done in the console are:

1. **Authentication → Sign-in method** — enable the providers you want
   (Google is the least friction for a personal platform).
2. **Authentication → Settings → Authorized domains** — add your custom domain.
3. Create an OAuth client and put its credentials in Secret Manager:

   ```sh
   echo -n "<client-id>"     | gcloud secrets versions add zino-oauth-client-id --data-file=-
   echo -n "<client-secret>" | gcloud secrets versions add zino-oauth-client-secret --data-file=-
   ```

Until step 3 is done, Open WebUI falls back to its own email/password login,
which is fine for a first boot — create your admin account that way. The first
account to register becomes the administrator.

## What Firebase is deliberately *not* used for

- **Firestore** — ZINO's state is relational and already lives in Cloud SQL.
  Adding Firestore would split the source of truth for no gain.
- **Cloud Functions** — ZINO deploys no code of its own. Agents and tools are
  authored inside Open WebUI and stored in its database (`docs/configuring.md`),
  so there is nothing for a function to run.
