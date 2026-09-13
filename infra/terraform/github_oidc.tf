# Workload Identity Federation: GitHub Actions authenticates to GCP with a
# short-lived OIDC token. No service-account JSON key is ever created, so there
# is no long-lived credential to leak from the repo or CI logs (ADR 0002).

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "zino-github"
  display_name              = "ZINO GitHub Actions"

  depends_on = [google_project_service.required]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Without this condition, any GitHub repository on the internet could exchange
  # a token for this pool. Scope it to ours.
  attribute_condition = "assertion.repository == '${var.github_repository}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "deployer" {
  account_id   = "zino-deployer"
  display_name = "ZINO CI deployer"

  depends_on = [google_project_service.required]
}

# Only workflow runs from our repository may impersonate the deployer.
resource "google_service_account_iam_member" "deployer_wif" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# ZINO builds no images, so CI never pushes to a registry and never deploys a
# Cloud Run revision — `terraform apply` does that. All CI publishes is the
# Firebase Hosting config, so that is the only role the deployer gets.
resource "google_project_iam_member" "deployer" {
  for_each = toset([
    "roles/firebasehosting.admin",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.deployer.email}"
}
