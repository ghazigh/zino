output "webui_url" {
  description = "Direct Cloud Run URL for Open WebUI (Firebase Hosting fronts this)."
  value       = google_cloud_run_v2_service.webui.uri
}

output "agents_url" {
  description = "Cloud Run URL of the ZINO agent gateway."
  value       = google_cloud_run_v2_service.agents.uri
}

output "public_url" {
  description = "The address users actually visit."
  value       = local.public_url
}

output "artifact_registry" {
  description = "Docker repository to push ZINO images to."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

output "sql_connection_name" {
  description = "Cloud SQL instance connection name."
  value       = google_sql_database_instance.main.connection_name
}

output "bucket_name" {
  description = "GCS bucket backing Open WebUI file storage."
  value       = google_storage_bucket.files.name
}

# --- Values to paste into GitHub repository settings ------------------------

output "github_workload_identity_provider" {
  description = "Set as the GitHub Actions variable GCP_WORKLOAD_IDENTITY_PROVIDER."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "github_deployer_service_account" {
  description = "Set as the GitHub Actions variable GCP_DEPLOYER_SA."
  value       = google_service_account.deployer.email
}
