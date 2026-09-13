# Upgrading Open WebUI

ZINO pins the upstream image (ADR 0001), so an upgrade is a version bump plus a
check that nothing we depend on moved.

## Procedure

1. **Read the upstream release notes** between your current tag and the target:
   <https://github.com/open-webui/open-webui/releases>. You are looking for
   three things specifically:
   - renamed or removed environment variables,
   - database migrations (these run automatically on boot, but they are one-way),
   - changes to the OpenAI-compatible provider handling, which is ZINO's
     integration surface.

2. **Back up the database first.** Migrations are not reversible.

   ```sh
   gcloud sql backups create --instance=zino-pg
   ```

3. **Bump the pin in both places** — they are deliberately separate so you can
   test locally before touching production:

   | File | Variable |
   |------|----------|
   | `.env` | `ZINO_OPENWEBUI_VERSION` |
   | `infra/terraform/variables.tf` | `openwebui_version` default |

4. **Test locally** against a throwaway database:

   ```sh
   make clean && make up
   ```

   Then check: login works, the `zino-echo` model appears in the picker and
   streams, file upload works, and a RAG query returns results.

5. **Apply.** `make tf-apply`, then watch the Cloud Run revision come up. If the
   startup probe fails, the old revision keeps serving — Cloud Run will not shift
   traffic to a revision that never became healthy.

## Verifying the config keys still exist

The env vars ZINO sets are read from upstream's `backend/open_webui/config.py`
and `env.py`. To confirm a key survived an upgrade:

```sh
git clone --depth 1 --branch <tag> --filter=blob:none --sparse \
  https://github.com/open-webui/open-webui /tmp/owui
cd /tmp/owui && git sparse-checkout set backend/open_webui
grep -n "STORAGE_PROVIDER\|VECTOR_DB\|OPENID_PROVIDER_URL" backend/open_webui/config.py
```

The keys ZINO depends on, verified against **v0.9.6**:

`DATABASE_URL`, `VECTOR_DB`, `PGVECTOR_DB_URL`, `STORAGE_PROVIDER`,
`GCS_BUCKET_NAME`, `ENABLE_OPENAI_API`, `OPENAI_API_BASE_URLS`,
`OPENAI_API_KEYS`, `WEBUI_NAME`, `WEBUI_SECRET_KEY`, `WEBUI_URL`,
`ENABLE_OAUTH_SIGNUP`, `OAUTH_CLIENT_ID`, `OAUTH_CLIENT_SECRET`,
`OPENID_PROVIDER_URL`, `OPENID_REDIRECT_URI`, `OAUTH_MERGE_ACCOUNTS_BY_EMAIL`.

> `OPENAI_API_BASE_URLS` and `OPENAI_API_KEYS` are **semicolon**-separated lists,
> and the two lists are matched by position. Adding a provider means adding an
> entry to both.
