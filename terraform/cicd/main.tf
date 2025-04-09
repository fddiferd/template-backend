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
  project = var.project_id
  region  = var.region
}

locals {
  region = var.region
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
  project = var.project_id
  role    = each.value
  member  = "user:${var.user_email}"
}

# IAM bindings for Cloud Build service account
resource "google_project_iam_member" "cloudbuild_roles" {
  for_each = toset([
    "roles/storage.objectViewer",
    "roles/storage.objectCreator",
    "roles/artifactregistry.writer",
    "roles/storage.admin",
    "roles/logging.logWriter",
    "roles/run.admin"
  ])
  project = var.project_id
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
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

# Get project information
data "google_project" "project" {
  project_id = var.project_id
}

resource "google_service_account" "cloudrun_sa" {
  account_id   = "cloudrun-${var.environment}-sa"
  display_name = "Cloud Run Service Account ${var.environment}"
}

resource "google_project_iam_member" "cloudrun_roles" {
  for_each = toset(["roles/run.admin", "roles/storage.admin", "roles/artifactregistry.writer", "roles/datastore.user", "roles/firebase.admin"])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudrun_sa.email}"
}

resource "google_artifact_registry_repository" "docker_repo" {
  location      = local.region
  repository_id = var.repo_name
  format        = "DOCKER"
  
  # This prevents errors when the repository already exists
  lifecycle {
    ignore_changes = [description]
    prevent_destroy = true
  }
}

resource "google_cloud_run_v2_service" "api_service" {
  name     = var.service_name
  location = local.region
  deletion_protection = false

  # This prevents errors when the service already exists
  lifecycle {
    ignore_changes = [template, traffic]
  }

  template {
    containers {
      image = "${local.region}-docker.pkg.dev/${var.project_id}/${var.repo_name}/${var.service_name}:latest"
      
      ports {
        container_port = var.api_port
      }

      env {
        name  = "HOST"
        value = var.api_host
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
          cpu    = var.cpu_limit
          memory = var.memory_limit
        }
      }

      startup_probe {
        tcp_socket {
          port = var.api_port
        }
        initial_delay_seconds = 0
        timeout_seconds      = 240
        period_seconds      = 240
        failure_threshold   = 1
      }
    }

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    max_instance_request_concurrency = var.request_concurrency
    timeout = "300s"
    service_account = google_service_account.cloudrun_sa.email
  }
}

resource "google_cloud_run_service_iam_member" "public_access" {
  location = google_cloud_run_v2_service.api_service.location
  project  = var.project_id
  service  = google_cloud_run_v2_service.api_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Cloud Build Triggers
# Development trigger (runs on push to any branch except main)
resource "google_cloudbuild_trigger" "dev_trigger" {
  count = var.environment == "dev" ? 1 : 0
  
  name        = "${var.project_id}-dev"
  description = "Build and deploy on any branch except main"
  
  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      branch = "^(?!main$).*$"
    }
  }
  
  filename = "cloudbuild.yaml"
  
  substitutions = {
    _SERVICE_NAME = var.service_name
    _REPO_NAME    = var.repo_name
    _REGION       = local.region
  }
}

# Staging trigger (runs on push to main)
resource "google_cloudbuild_trigger" "staging_trigger" {
  count = var.environment == "staging" ? 1 : 0
  
  name        = "${var.project_id}-staging"
  description = "Build and deploy on push to main branch"
  
  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      branch = "main"
    }
  }
  
  filename = "cloudbuild.yaml"
  
  substitutions = {
    _SERVICE_NAME = var.service_name
    _REPO_NAME    = var.repo_name
    _REGION       = local.region
  }
}

# Production trigger (runs on tags starting with v)
resource "google_cloudbuild_trigger" "prod_trigger" {
  count = var.environment == "prod" ? 1 : 0
  
  name        = "${var.project_id}-prod"
  description = "Build and deploy on tags starting with v"
  
  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      tag = "^v.*$"
    }
  }
  
  filename = "cloudbuild.yaml"
  
  substitutions = {
    _SERVICE_NAME = var.service_name
    _REPO_NAME    = var.repo_name
    _REGION       = local.region
  }
}
