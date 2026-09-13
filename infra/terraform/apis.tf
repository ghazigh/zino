# Services ZINO depends on. Enabling is idempotent; disable_on_destroy is off so
# tearing down ZINO does not break anything else in the project.
locals {
  required_services = [
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
    # iam creates service accounts and workload identity pools.
    # iamcredentials is a different service — it mints short-lived tokens.
    # Both are needed; enabling only the second is what broke the first apply.
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    # Project-level IAM bindings go through this one.
    "cloudresourcemanager.googleapis.com",
    "firebase.googleapis.com",
    "firebasehosting.googleapis.com",
    "identitytoolkit.googleapis.com",
  ]
}

resource "google_project_service" "required" {
  for_each = toset(local.required_services)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
