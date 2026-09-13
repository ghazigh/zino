# A minimal VPC so Cloud SQL can take a private IP instead of a public one.

resource "google_compute_network" "main" {
  name                    = "zino-net"
  auto_create_subnetworks = true

  depends_on = [google_project_service.required]
}

resource "google_compute_global_address" "private_ip" {
  name          = "zino-sql-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "main" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip.name]
}
