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

  # Terraform state holds database passwords in plaintext. Keep it in a private,
  # versioned GCS bucket — never on a laptop, never in git.
  # Create the bucket once by hand, then uncomment and `terraform init -migrate-state`.
  #
  # backend "gcs" {
  #   bucket = "zino-tfstate-CHANGEME"
  #   prefix = "zino/prod"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
