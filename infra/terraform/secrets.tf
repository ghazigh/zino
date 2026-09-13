# Secrets live in Secret Manager and are mounted into Cloud Run as environment
# variables at deploy time. Values that Terraform generates are stored here;
# values you supply (the model provider key) are created empty and filled in
# out of band so they never enter Terraform state.

resource "random_password" "webui_secret_key" {
  length  = 64
  special = false
}

resource "random_password" "gateway_api_key" {
  length  = 48
  special = false
}

locals {
  # Secrets Terraform owns the value of.
  managed_secrets = {
    webui-secret-key = random_password.webui_secret_key.result
    gateway-api-key  = random_password.gateway_api_key.result
    database-url     = local.database_url
  }

  # Secrets you populate yourself, so their values never enter Terraform state:
  #   echo -n "sk-..." | gcloud secrets versions add zino-upstream-api-key --data-file=-
  # The OAuth pair comes from the Firebase console (infra/firebase/README.md).
  unmanaged_secrets = [
    "upstream-api-key",
    "oauth-client-id",
    "oauth-client-secret",
  ]
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
