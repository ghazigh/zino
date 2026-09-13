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
  description = <<-EOT
    Cloud SQL machine type. db-f1-micro is the cheapest and is adequate for a
    personal platform.

    Tied to the edition, which sql.tf pins to ENTERPRISE: shared-core tiers
    (db-f1-micro, db-g1-small) exist only there. ENTERPRISE_PLUS requires a
    db-perf-optimized-N-* tier and costs far more.
  EOT
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

# --- Sizing -----------------------------------------------------------------
# Defaults are tuned for lowest cost on a personal platform with a handful of
# users. See docs/cost.md before changing them.

variable "min_instances" {
  description = <<-EOT
    Warm Cloud Run instances. 0 means the service scales to zero when unused and
    costs nothing while idle, at the price of a cold start (roughly 30-60s)
    on the first request after a quiet period.

    Set to 1 to keep it always responsive; that is the single biggest line on
    the bill, so do it deliberately.
  EOT
  type        = number
  default     = 0
}

variable "max_instances" {
  description = <<-EOT
    Must stay at 1. Open WebUI holds chat websockets, and fanning those across
    instances needs Redis (WEBSOCKET_MANAGER=redis), which ZINO does not run.
    A second instance would drop live streams rather than share load.
  EOT
  type        = number
  default     = 1

  validation {
    condition     = var.max_instances == 1
    error_message = "max_instances must be 1 until Redis is added for websocket fan-out."
  }
}

variable "cpu" {
  description = "vCPU per instance. With min_instances = 0 this is billed only while serving, so a larger value mostly buys faster cold starts rather than a bigger bill."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory per instance. Open WebUI loads a local embedding model for RAG, so below 2Gi it starts failing on knowledge-base queries."
  type        = string
  default     = "2Gi"
}
