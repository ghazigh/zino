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
      # The instance has a public address but no authorised networks, so no
      # host on the internet may open a connection to it. The only way in is
      # Cloud Run's Cloud SQL connector, which authenticates as this project's
      # service account through the Cloud SQL Admin API.
      #
      # Private IP would be tighter still, but Cloud Run's socket connector
      # cannot route to a private-only instance unless the service also has
      # Direct VPC egress into the same network. Adding that is the upgrade
      # path; without it the deploy succeeds and the app cannot reach its
      # database.
      ipv4_enabled = true

      # No `authorized_networks` block is declared, and that is the point:
      # with none declared, no address range is permitted to open a connection.
      # It is a block rather than an argument, so "allow nothing" is expressed
      # by its absence, not by an empty list.

      # Reject any connection that is not TLS.
      ssl_mode = "ENCRYPTED_ONLY"
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

  depends_on = [google_project_service.required]
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
