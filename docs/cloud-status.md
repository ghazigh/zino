# Status of the GCP deployment

Paused, not finished. This records exactly where it stopped so picking it up
later does not mean re-deriving it.

## What works

- `scripts/bootstrap.sh` runs clean: project, billing, APIs, Terraform state
  bucket, Firebase, generated config.
- `terraform init`, `validate` and `plan` all succeed — 30 resources planned.
- `terraform apply` gets partway: the GCS bucket, the API enablements and the
  generated passwords were created.

## What is left in the project

Nothing billable. The database and Cloud Run service both failed before
creation, so there is no compute and no storage in use:

| Exists | Cost |
|--------|------|
| Two empty GCS buckets (state + files) | ~$0 |
| Enabled APIs | free |
| Terraform state | ~$0 |

To remove it all anyway:

```sh
./scripts/destroy.sh
gcloud storage rm --recursive gs://<project>-zino-tfstate
```

## Where it stopped

Two errors on the first apply, both now fixed but not yet re-run:

1. **`iam.googleapis.com` was not enabled.** The API list had
   `iamcredentials.googleapis.com`, which is a different service. Fixed in
   `apis.tf` and `bootstrap.sh`, with `depends_on` added to the service
   accounts.
2. **Cloud SQL rejected `db-f1-micro`.** New Postgres instances default to the
   `ENTERPRISE_PLUS` edition, which has no shared-core tiers. Fixed by pinning
   `edition = "ENTERPRISE"` in `sql.tf`.

## To resume

```sh
./scripts/deploy.sh
```

Terraform converges from the partial state; nothing is created twice.

## The untested part

Even after a successful apply, one thing has never been exercised: **Open WebUI
actually starting on Cloud Run and reaching Cloud SQL.** That is the step most
likely to need work, and the reason this is "a strong starting point" rather
than "a working deployment". If the container starts and fails, the logs are:

```sh
gcloud run services logs read zino-webui --region=europe-west1 --limit=50
```

## Why it was paused

Each error could only be found by running against real GCP, which meant a
round trip per error. Running locally needs none of this, and for a handful of
users it gives the same product.
