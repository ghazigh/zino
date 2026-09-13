variable "project_id" {
  description = "GCP project ID hosting ZINO."
  type        = string
}

variable "region" {
  description = "Region for Cloud Run, Cloud SQL and Artifact Registry."
  type        = string
  default     = "europe-west1"
}

variable "openwebui_version" {
  description = "Pinned upstream Open WebUI image tag. See docs/upgrading.md before changing."
  type        = string
  default     = "v0.9.6"
}

variable "domain" {
  description = "Custom domain served by Firebase Hosting, e.g. zino.example.com. Empty to use the default Firebase domain."
  type        = string
  default     = ""
}

variable "db_tier" {
  description = "Cloud SQL machine type. db-f1-micro is the cheapest and is adequate for a personal platform."
  type        = string
  default     = "db-f1-micro"
}

variable "github_repository" {
  description = "owner/repo allowed to deploy via Workload Identity Federation."
  type        = string
  default     = "ghazigh/zino"
}

variable "enable_oidc" {
  description = <<-EOT
    Use Firebase Auth (OIDC) for login instead of Open WebUI's built-in
    email/password accounts.

    Left off by default because enabling it is NOT fully scriptable: creating
    the OAuth client is a Google Cloud console step, and neither gcloud nor the
    Firebase CLI can configure sign-in providers. Turn it on once you have
    populated the zino-oauth-client-id and zino-oauth-client-secret secrets —
    see scripts/enable-oidc.sh.
  EOT
  type        = bool
  default     = false
}
