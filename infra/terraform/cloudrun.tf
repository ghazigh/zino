# Two Cloud Run services: upstream Open WebUI, and the ZINO agent gateway.

locals {
  agents_url = google_cloud_run_v2_service.agents.uri

  # Placeholder keeps `terraform plan` working before CI has pushed a real
  # image; CI passes -var agents_image=<digest> on every deploy.
  agents_image = var.agents_image != "" ? var.agents_image : "us-docker.pkg.dev/cloudrun/container/hello"

  # Where users actually reach ZINO. Firebase Hosting serves the custom domain
  # when one is set, otherwise the project's default Firebase domain.
  public_url = var.domain != "" ? "https://${var.domain}" : "https://${var.project_id}.web.app"
}

# --- ZINO agent gateway -----------------------------------------------------

resource "google_cloud_run_v2_service" "agents" {
  name     = "zino-agents"
  location = var.region

  # Ingress is open because Open WebUI authenticates to this gateway with a
  # bearer token (its "OpenAI API key"), not a Google-signed ID token — so
  # Cloud Run IAM cannot be the gate here. The gate is ZINO_API_KEY, which the
  # gateway compares in constant time and which fails closed when unset in
  # production. To close ingress instead, put the WebUI service on Direct VPC
  # egress and reach this one over an internal load balancer.
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.agents.email

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      image = local.agents_image

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      env {
        name  = "ZINO_ENV"
        value = "production"
      }
      env {
        name  = "ZINO_UPSTREAM_BASE_URL"
        value = var.upstream_base_url
      }
      env {
        name  = "ZINO_UPSTREAM_MODEL"
        value = var.upstream_model
      }
      env {
        name = "ZINO_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.managed["gateway-api-key"].secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "ZINO_UPSTREAM_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.unmanaged["upstream-api-key"].secret_id
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get {
          path = "/healthz"
        }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 6
      }
    }
  }

  lifecycle {
    # CI deploys new revisions by image; do not let `terraform apply` roll the
    # service back to whatever tag is in the tfvars.
    ignore_changes = [template[0].containers[0].image, client, client_version]
  }

  depends_on = [google_project_service.required]
}

# --- Open WebUI -------------------------------------------------------------

resource "google_cloud_run_v2_service" "webui" {
  name     = "zino-webui"
  location = var.region

  # Firebase Hosting fronts this; it reaches Cloud Run over Google's network.
  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.webui.email

    scaling {
      # One warm instance: Open WebUI holds chat websockets, so scaling to zero
      # drops live streams. max=1 because multi-instance websocket fan-out needs
      # Redis (WEBSOCKET_MANAGER=redis) — see ADR 0002.
      min_instance_count = 1
      max_instance_count = 1
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
          cpu    = "2"
          memory = "4Gi"
        }
        # Required with min_instance_count > 0 so the warm instance stays
        # responsive instead of being throttled between requests.
        cpu_idle = false
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

      # State lives in Cloud SQL and GCS, never on the container filesystem.
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

      # ZINO agents, registered as an OpenAI-compatible provider.
      env {
        name  = "ENABLE_OPENAI_API"
        value = "true"
      }
      env {
        name  = "OPENAI_API_BASE_URLS"
        value = "${local.agents_url}/v1"
      }
      env {
        name  = "ENABLE_OLLAMA_API"
        value = "false"
      }

      # --- Firebase Auth as the OIDC identity provider ---
      env {
        name  = "ENABLE_OAUTH_SIGNUP"
        value = "true"
      }
      env {
        name  = "OAUTH_MERGE_ACCOUNTS_BY_EMAIL"
        value = "true"
      }
      env {
        name  = "OAUTH_PROVIDER_NAME"
        value = "ZINO"
      }
      env {
        name  = "OPENID_PROVIDER_URL"
        value = "https://securetoken.google.com/${var.project_id}/.well-known/openid-configuration"
      }
      env {
        name  = "OPENID_REDIRECT_URI"
        value = "${local.public_url}/oauth/oidc/callback"
      }

      # Sourced from secrets Terraform does not own the value of; the OAuth
      # pair stays empty until you add a version, and Open WebUI then falls
      # back to its built-in email/password login.
      dynamic "env" {
        for_each = {
          OAUTH_CLIENT_ID     = "oauth-client-id"
          OAUTH_CLIENT_SECRET = "oauth-client-secret"
        }
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
          OPENAI_API_KEYS  = "gateway-api-key"
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

# Firebase Hosting terminates auth at the edge; Open WebUI does its own login,
# so the Cloud Run service itself is public and WEBUI_AUTH stays on.
resource "google_cloud_run_v2_service_iam_member" "webui_public" {
  location = google_cloud_run_v2_service.webui.location
  name     = google_cloud_run_v2_service.webui.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Invocable without Google IAM for the reason given on `ingress` above. The
# request is still rejected by the gateway unless it carries the correct
# ZINO_API_KEY bearer token.
resource "google_cloud_run_v2_service_iam_member" "agents_invoker" {
  location = google_cloud_run_v2_service.agents.location
  name     = google_cloud_run_v2_service.agents.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
