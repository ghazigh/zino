# Object storage for Open WebUI uploads (STORAGE_PROVIDER=gcs).

resource "google_storage_bucket" "files" {
  name                        = "${var.project_id}-zino-files"
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true

  # Nothing here should ever be world-readable: uploads are personal documents.
  public_access_prevention = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = "zino"
  description   = "ZINO container images"
  format        = "DOCKER"

  # Keep the registry from growing without bound as CI pushes every commit.
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  depends_on = [google_project_service.required]
}
