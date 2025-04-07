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
  project = "wedge-golf-${var.environment}"
  region  = "us-central1"
}

# IAM bindings for the user account
resource "google_project_iam_member" "user_roles" {
  for_each = toset([
    "roles/iam.serviceAccountAdmin",
    "roles/artifactregistry.admin",
    "roles/run.admin",
    "roles/storage.admin",
    "roles/iam.serviceAccountUser",
    "roles/logging.logWriter"
  ])
  project = "wedge-golf-${var.environment}"
  role    = each.value
  member  = "user:fddiferd@gmail.com"
}

# IAM bindings for Cloud Build service account
resource "google_project_iam_member" "cloudbuild_roles" {
  for_each = toset([
    "roles/storage.objectViewer",
    "roles/storage.objectCreator",
    "roles/artifactregistry.writer",
    "roles/storage.admin",
    "roles/logging.logWriter"
  ])
  project = "wedge-golf-${var.environment}"
  role    = each.value
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

# IAM bindings for Compute service account
resource "google_project_iam_member" "compute_roles" {
  for_each = toset([
    "roles/artifactregistry.writer",
    "roles/storage.admin",
    "roles/logging.logWriter"
  ])
  project = "wedge-golf-${var.environment}"
  role    = each.value
  member  = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

# Get project information
data "google_project" "project" {
  project_id = "wedge-golf-${var.environment}"
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
  repository_id = "wedge-api"
  format        = "DOCKER"
}

resource "google_cloud_run_v2_service" "api_service" {
  name     = "wedge-api"
  location = "us-central1"
  deletion_protection = false

  template {
    containers {
      image = "gcr.io/wedge-golf-${var.environment}/wedge-api:latest"
      
      ports {
        container_port = 8000
      }

      env {
        name  = "HOST"
        value = "0.0.0.0"
      }

      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }

      env {
        name  = "FIREBASE_CRED_PATH"
        value = "service_accounts/firebase-${var.environment}.json"
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
      }

      startup_probe {
        tcp_socket {
          port = 8000
        }
        initial_delay_seconds = 0
        timeout_seconds      = 240
        period_seconds      = 240
        failure_threshold   = 1
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    max_instance_request_concurrency = 80
    timeout = "300s"
    service_account = "cloudrun-${var.environment}-sa@wedge-golf-${var.environment}.iam.gserviceaccount.com"
  }
}

resource "google_cloud_run_service_iam_member" "public_access" {
  location = google_cloud_run_v2_service.api_service.location
  project  = "wedge-golf-${var.environment}"
  service  = google_cloud_run_v2_service.api_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
