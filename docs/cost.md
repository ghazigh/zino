# What ZINO costs

Configured for lowest cost on a personal platform with a few users. The numbers
below are estimates from Google's published rates for `europe-west1`, not
quotes — confirm against the
[pricing calculator](https://cloud.google.com/products/calculator) before
relying on them. The *shape* is the reliable part: **the database is the floor,
and the server is whatever you use.**

## Default configuration

| | |
|---|---|
| Cloud Run | scales to zero, 1 vCPU, 2 GiB, request-based billing |
| Cloud SQL | `db-f1-micro`, 10 GB SSD, zonal, daily backups + PITR |

### Estimated monthly

| Item | Cost | Notes |
|------|------|-------|
| **Cloud SQL** | **~$9–12** | Runs 24/7. Cannot scale to zero. This is your floor. |
| **Cloud Run** | **~$0–15** | Billed only while serving. Free tier covers light use. |
| Storage, secrets, hosting | ~$1 | Firebase Hosting's free tier is generous |
| **Total** | **~$10–25** | |

Not included: what your LLM provider charges. That is usually the largest number
on this page once you start using ZINO in earnest, and it is billed by them, not
by Google.

## The trade you accepted

With `min_instances = 0` the server shuts down when nobody is using it. The next
person to open ZINO waits roughly **30–60 seconds** while it starts — database
migrations and the embedding model load on every cold start. `startup_cpu_boost`
is on to keep that as short as possible.

After that first request it stays warm for a while, so a working session feels
normal. It is the first message after a quiet spell that is slow.

## What actually drives the Cloud Run number

Request-based billing charges for time spent *processing requests*. For a chat
app, that includes the whole streamed answer — and **an open websocket counts as
an in-flight request for as long as the browser tab holds it**.

So the meaningful variable is not how many messages you send, it is how long
ZINO tabs sit open. A tab left open all day bills like an all-day request.

If the bill is higher than expected, that is the first thing to check.

## Changing it

Edit `infra/terraform/terraform.tfvars`, then `./scripts/deploy.sh`.

| Want | Change | Roughly |
|------|--------|---------|
| Always instant, no cold start | `min_instances = 1` | **+$60–100/mo** — it forces always-allocated CPU |
| Faster cold starts | `cpu = "2"` | Little change while scaled to zero; you pay that rate only during the seconds it is working |
| Cheaper still | see below | |

`max_instances` is fixed at 1 and validated as such: Open WebUI holds chat
websockets, and spreading them over instances needs Redis, which ZINO does not
run. A second instance would drop live streams, not share load. One instance
serves several concurrent users fine — Cloud Run's default is 80 concurrent
requests per instance.

## If you want it cheaper than this

The database is the only thing left to cut, and each option costs you something
real:

- **Drop point-in-time recovery** (`sql.tf`) — saves a little on log storage.
  Costs you the ability to rewind to a moment; daily backups remain. Remember
  that your agents, tools and provider keys live in this database.
- **Move to an external free-tier Postgres** (Neon, Supabase) — takes Cloud SQL
  to zero and gets you close to $1/month overall. Costs you having everything in
  one project under one bill, and adds a dependency outside GCP. It works because
  ZINO reaches the database purely through `DATABASE_URL`, so only that secret
  and the pgvector settings change.

## Watch the bill

Set a budget alert before you forget:

```sh
gcloud billing budgets create \
  --billing-account=<ACCOUNT_ID> \
  --display-name="ZINO" \
  --budget-amount=30USD \
  --threshold-rule=percent=50 \
  --threshold-rule=percent=100
```

This emails you; it does not cap spending. Nothing in GCP does — a budget is an
alarm, not a limit.
