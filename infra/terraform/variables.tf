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

variable "agents_image" {
  description = <<-EOT
    Full image reference for the ZINO agent gateway, including digest or tag.
    CI overrides this per deploy; the default only exists so `terraform plan`
    works before the first image is pushed.
  EOT
  type        = string
  default     = ""
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

variable "upstream_model" {
  description = "Default model the ZINO assistant agent calls."
  type        = string
  default     = "gpt-4o-mini"
}

variable "upstream_base_url" {
  description = "OpenAI-compatible base URL the agents call."
  type        = string
  default     = "https://api.openai.com/v1"
}
