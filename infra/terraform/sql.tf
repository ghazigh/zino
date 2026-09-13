# Cloud SQL for PostgreSQL. Backs both the Open WebUI application database and
# the pgvector store (ADR 0002) — one stateful service instead of two.

resource "random_password" "db" {
  length  = 32
  special = false # keeps the password safe to embed in a DSN without escaping
}

resource "google_sql_database_instance" "main" {
  name             = "zino-pg"
  database_version = "POSTGRES_16"
  region           = var.region

  # Guard against a stray `terraform destroy` taking the database with it.
  deletion_protection = true

  settings {
    tier              = var.db_tier
    availability_type = "ZONAL" # personal platform; REGIONAL doubles the cost
    disk_size         = 10
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
    }

    ip_configuration {
      # No public IP. Cloud Run reaches the instance over the Cloud SQL
      # connector, so nothing needs to be exposed to the internet.
      ipv4_enabled = false
      # Private IP requires a VPC peering; for a single-host personal setup the
      # connector-only path below is simpler and is what Cloud Run uses.
      private_network = google_compute_network.main.id
    }

    maintenance_window {
      day  = 7 # Sunday
      hour = 4
    }

    database_flags {
      name  = "max_connections"
      value = "50"
    }
  }

  depends_on = [
    google_project_service.required,
    google_service_networking_connection.main,
  ]
}

resource "google_sql_database" "zino" {
  name     = "zino"
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "zino" {
  name     = "zino"
  instance = google_sql_database_instance.main.name
  password = random_password.db.result
}

locals {
  # Cloud Run mounts the Cloud SQL socket under /cloudsql/<connection name>.
  # psycopg2 takes the socket directory via the `host` query parameter.
  database_url = format(
    "postgresql://%s:%s@/%s?host=/cloudsql/%s",
    google_sql_user.zino.name,
    random_password.db.result,
    google_sql_database.zino.name,
    google_sql_database_instance.main.connection_name,
  )
}
