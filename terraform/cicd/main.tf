
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

provider "google" {
  credentials = file("../../firebase-${var.environment}.json")
  project     = "wedge-golf-${var.environment}"
  region      = "us-central1"
}

resource "google_service_account" "cloudrun_sa" {
  account_id   = "cloudrun-${var.environment}-sa"
  display_name = "Cloud Run Service Account ${var.environment}"
}

resource "google_project_iam_member" "cloudrun_roles" {
  for_each = toset(["roles/run.admin", "roles/storage.admin", "roles/artifactregistry.writer", "roles/datastore.user", "roles/firebase.admin"])
  project = "wedge-golf-${var.environment}"
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudrun_sa.email}"
}

resource "google_artifact_registry_repository" "docker_repo" {
  location      = "us-central1"
  repository_id = "fastapi-app"
  format        = "DOCKER"
}

resource "google_cloud_run_v2_service" "fastapi_service" {
  name     = "fastapi-app-${var.environment}"
  location = "us-central1"

  template {
    containers {
      image = "us-central1-docker.pkg.dev/wedge-golf-${var.environment}/fastapi-app/fastapi:latest"
      ports {
        container_port = 8000
      }
    }
    service_account = google_service_account.cloudrun_sa.email
  }
}

resource "google_cloud_run_service_iam_member" "public_access" {
  location = "us-central1"
  project  = "wedge-golf-${var.environment}"
  service  = google_cloud_run_v2_service.fastapi_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
