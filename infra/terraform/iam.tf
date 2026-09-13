# One service account per Cloud Run service, so a compromised agent tool cannot
# reach the WebUI's database credentials (ADR 0002).

resource "google_service_account" "webui" {
  account_id   = "zino-webui"
  display_name = "ZINO Open WebUI runtime"
}

resource "google_service_account" "agents" {
  account_id   = "zino-agents"
  display_name = "ZINO agent gateway runtime"
}

# --- Open WebUI: database, its own secrets, and the uploads bucket -----------

resource "google_project_iam_member" "webui_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.webui.email}"
}

resource "google_storage_bucket_iam_member" "webui_bucket" {
  bucket = google_storage_bucket.files.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.webui.email}"
}

resource "google_secret_manager_secret_iam_member" "webui_secrets" {
  for_each = toset(["webui-secret-key", "gateway-api-key", "database-url"])

  secret_id = google_secret_manager_secret.managed[each.value].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.webui.email}"
}

resource "google_secret_manager_secret_iam_member" "webui_oauth" {
  for_each = toset(["oauth-client-id", "oauth-client-secret"])

  secret_id = google_secret_manager_secret.unmanaged[each.value].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.webui.email}"
}

# --- Agent gateway: only the two secrets it actually needs -------------------

resource "google_secret_manager_secret_iam_member" "agents_gateway_key" {
  secret_id = google_secret_manager_secret.managed["gateway-api-key"].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.agents.email}"
}

resource "google_secret_manager_secret_iam_member" "agents_upstream_key" {
  secret_id = google_secret_manager_secret.unmanaged["upstream-api-key"].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.agents.email}"
}

# Note: the agent gateway deliberately has no cloudsql.client and no bucket
# access. Give it those only when an agent genuinely needs to read them.
