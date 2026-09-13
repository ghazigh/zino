# One Cloud Run service: the upstream Open WebUI image, unmodified.
#
# Model providers and agents are NOT configured here. Open WebUI persists those
# in its own database (ENABLE_PERSISTENT_CONFIG defaults to true), so they are
# set once through the admin UI and survive every redeploy. Putting them in env
# would only seed the very first boot and then be silently overridden — see
# docs/configuring.md.

locals {
  # Where users actually reach ZINO. Firebase Hosting serves the custom domain
  # when one is set, otherwise the project's default Firebase domain.
  public_url = var.domain != "" ? "https://${var.domain}" : "https://${var.project_id}.web.app"
}

resource "google_cloud_run_v2_service" "webui" {
  name     = "zino-webui"
  location = var.region

  # Firebase Hosting fronts this; it reaches Cloud Run over Google's network.
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.webui.email

    scaling {
      # Defaults to scale-to-zero: nothing is billed while idle. See docs/cost.md.
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    containers {
      image = "ghcr.io/open-webui/open-webui:${var.openwebui_version}"

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        # cpu_idle = true is request-based billing: CPU is charged only while a
        # request is in flight, which is what makes scale-to-zero cheap. It is
        # forced off when instances are kept warm, since a throttled warm
        # instance is the worst of both — paid for, and still slow to respond.
        cpu_idle = var.min_instances == 0

        # Extra CPU during container startup only. It is what keeps a
        # scale-to-zero cold start tolerable, and is billed for those seconds
        # alone — so with min_instances = 0 it is close to free.
        startup_cpu_boost = true
      }

      env {
        name  = "WEBUI_NAME"
        value = "ZINO"
      }
      env {
        name  = "ENV"
        value = "prod"
      }
      env {
        name  = "WEBUI_URL"
        value = local.public_url
      }

      # --- State: none of it on the container filesystem ---
      env {
        name  = "VECTOR_DB"
        value = "pgvector"
      }
      env {
        name  = "STORAGE_PROVIDER"
        value = "gcs"
      }
      env {
        name  = "GCS_BUCKET_NAME"
        value = google_storage_bucket.files.name
      }

      # --- Login ---
      # Off by default: Open WebUI's own email/password accounts are used, which
      # need no configuration at all. When enable_oidc is true these switch the
      # app to Firebase Auth.
      #
      # Unlike most settings, OAuth is NOT persisted to the database
      # (ENABLE_OAUTH_PERSISTENT_CONFIG defaults to false upstream), so these
      # env vars stay authoritative on every boot. Login config belongs in
      # Terraform, not in a database row.
      dynamic "env" {
        for_each = var.enable_oidc ? {
          ENABLE_OAUTH_SIGNUP           = "true"
          OAUTH_MERGE_ACCOUNTS_BY_EMAIL = "true"
          OAUTH_PROVIDER_NAME           = "ZINO"
          OPENID_PROVIDER_URL           = "https://securetoken.google.com/${var.project_id}/.well-known/openid-configuration"
          OPENID_REDIRECT_URI           = "${local.public_url}/oauth/oidc/callback"
        } : {}
        content {
          name  = env.key
          value = env.value
        }
      }

      # The OAuth client, from Secret Manager. Only present with enable_oidc.
      dynamic "env" {
        for_each = var.enable_oidc ? {
          OAUTH_CLIENT_ID     = "oauth-client-id"
          OAUTH_CLIENT_SECRET = "oauth-client-secret"
        } : {}
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.unmanaged[env.value].secret_id
              version = "latest"
            }
          }
        }
      }

      dynamic "env" {
        for_each = {
          DATABASE_URL     = "database-url"
          PGVECTOR_DB_URL  = "database-url"
          WEBUI_SECRET_KEY = "webui-secret-key"
        }
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.managed[env.value].secret_id
              version = "latest"
            }
          }
        }
      }

      startup_probe {
        http_get {
          path = "/health"
        }
        # Open WebUI runs database migrations on first boot; give it room.
        initial_delay_seconds = 20
        period_seconds        = 10
        failure_threshold     = 30
        timeout_seconds       = 5
      }
    }

    # Migrations plus model loading exceed the 5-minute default on a cold start.
    timeout = "600s"
  }

  lifecycle {
    ignore_changes = [client, client_version]
  }

  depends_on = [
    google_project_service.required,
    google_sql_database.zino,
    google_sql_user.zino,
  ]
}

# Firebase Hosting terminates nothing; Open WebUI does its own login, so the
# Cloud Run service is publicly invocable and WEBUI_AUTH stays on.
resource "google_cloud_run_v2_service_iam_member" "webui_public" {
  location = google_cloud_run_v2_service.webui.location
  name     = google_cloud_run_v2_service.webui.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
