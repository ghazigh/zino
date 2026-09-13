# Runtime identity for the Open WebUI Cloud Run service.

resource "google_service_account" "webui" {
  account_id   = "zino-webui"
  display_name = "ZINO Open WebUI runtime"
}

resource "google_project_iam_member" "webui_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.webui.email}"
}

# Open WebUI reaches the bucket with Application Default Credentials — on Cloud
# Run that is this service account, so no key file is needed.
resource "google_storage_bucket_iam_member" "webui_bucket" {
  bucket = google_storage_bucket.files.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.webui.email}"
}

resource "google_secret_manager_secret_iam_member" "webui_secrets" {
  for_each = toset(["webui-secret-key", "database-url"])

  secret_id = google_secret_manager_secret.managed[each.value].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.webui.email}"
}

resource "google_secret_manager_secret_iam_member" "webui_oauth" {
  for_each = toset(local.unmanaged_secrets)

  secret_id = google_secret_manager_secret.unmanaged[each.value].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.webui.email}"
}
