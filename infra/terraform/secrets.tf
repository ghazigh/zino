# Secrets live in Secret Manager and are mounted into Cloud Run as environment
# variables. Values Terraform generates are stored here; values you supply are
# created empty and filled in out of band so they never enter Terraform state.
#
# Note what is NOT here: model provider API keys. Those are entered in the Open
# WebUI admin UI and stored encrypted in its own database, so they are managed
# where you manage the connections themselves.

resource "random_password" "webui_secret_key" {
  length  = 64
  special = false
}

locals {
  # Secrets Terraform owns the value of.
  managed_secrets = {
    webui-secret-key = random_password.webui_secret_key.result
    database-url     = local.database_url
  }

  # Secrets you populate yourself. Only created when OIDC login is enabled;
  # see scripts/enable-oidc.sh, which creates them and prompts for the values.
  unmanaged_secrets = var.enable_oidc ? [
    "oauth-client-id",
    "oauth-client-secret",
  ] : []
}

resource "google_secret_manager_secret" "managed" {
  for_each = local.managed_secrets

  secret_id = "zino-${each.key}"
  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "managed" {
  for_each = local.managed_secrets

  secret      = google_secret_manager_secret.managed[each.key].id
  secret_data = each.value
}

resource "google_secret_manager_secret" "unmanaged" {
  for_each = toset(local.unmanaged_secrets)

  secret_id = "zino-${each.value}"
  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}
