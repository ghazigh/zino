terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # The GCS backend is NOT declared here. Terraform state holds the generated
  # database password in plaintext, so it belongs in a private, versioned
  # bucket — and that bucket's name depends on your project ID.
  # scripts/bootstrap.sh creates the bucket and writes backend.tf.
}

provider "google" {
  project = var.project_id
  region  = var.region
}
