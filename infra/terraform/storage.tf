# Object storage for Open WebUI uploads (STORAGE_PROVIDER=gcs).
#
# There is no Artifact Registry here: ZINO ships no container of its own, it
# runs the upstream image straight from ghcr.io.

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
