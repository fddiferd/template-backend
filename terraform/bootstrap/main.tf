terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.0"
    }
  }
}

provider "google" {
  # Use Application Default Credentials or environment variables instead
  # Delete or comment out the credentials line
}

provider "google-beta" {
  # Use Application Default Credentials or environment variables instead
  # Delete or comment out the credentials line
}

# The projects already exist, so we're referencing them directly without creation
resource "google_firebase_project" "default" {
  for_each = var.project_ids

  provider = google-beta
  project  = each.value
}

resource "google_project_service" "firestore_api" {
  for_each = var.project_ids

  project = each.value
  service = "firestore.googleapis.com"
}
