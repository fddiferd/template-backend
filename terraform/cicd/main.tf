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

# Data source for existing service account - prevents recreation errors
data "google_service_account" "cloudrun_sa" {
  account_id = "cloudrun-${var.environment}-sa"
  project    = var.project_id
}

# IAM bindings for the user account
resource "google_project_iam_member" "user_roles" {
  for_each = toset([
    "roles/iam.serviceAccountAdmin",
    "roles/artifactregistry.admin",
    "roles/run.admin",
    "roles/storage.admin",
    "roles/iam.serviceAccountUser",
    "roles/logging.logWriter",
    "roles/firebase.admin"
  ])
  project = var.project_id
  role    = each.value
  member  = "user:${var.user_email}"
}

# Get project information
data "google_project" "project" {
  project_id = var.project_id
}

# IAM bindings for Cloud Build service account
resource "google_project_iam_member" "cloudbuild_roles" {
  for_each = toset([
    "roles/storage.objectViewer",
    "roles/storage.objectCreator",
    "roles/artifactregistry.writer",
    "roles/artifactregistry.admin", 
    "roles/storage.admin",
    "roles/logging.logWriter",
    "roles/run.admin",
    "roles/firebase.admin"
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

# IAM bindings for Cloud Run service account
resource "google_project_iam_member" "cloudrun_roles" {
  for_each = toset([
    "roles/run.admin", 
    "roles/run.developer",
    "roles/run.invoker", 
    "roles/storage.admin", 
    "roles/artifactregistry.writer",
    "roles/artifactregistry.admin", 
    "roles/logging.logWriter",
    "roles/datastore.user", 
    "roles/firebase.admin"
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${data.google_service_account.cloudrun_sa.email}"
}

# Data source for existing artifact registry
data "google_artifact_registry_repository" "existing_repo" {
  location      = local.region
  repository_id = var.repo_name
  project       = var.project_id
}

# Add specific repository-level permissions for Cloud Build service account
resource "google_artifact_registry_repository_iam_member" "cloudbuild_repo_access" {
  count      = var.skip_resource_creation ? 0 : 1
  repository = data.google_artifact_registry_repository.existing_repo.name
  location   = data.google_artifact_registry_repository.existing_repo.location
  project    = var.project_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"

  depends_on = [data.google_artifact_registry_repository.existing_repo]
}

# Add specific repository-level permissions for Cloud Run service account
resource "google_artifact_registry_repository_iam_member" "cloudrun_repo_access" {
  count      = var.skip_resource_creation ? 0 : 1
  repository = data.google_artifact_registry_repository.existing_repo.name
  location   = data.google_artifact_registry_repository.existing_repo.location
  project    = var.project_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${data.google_service_account.cloudrun_sa.email}"

  depends_on = [data.google_artifact_registry_repository.existing_repo]
}

# Allow service account to act as itself (fixing iam.serviceAccounts.actAs permission issue)
resource "google_service_account_iam_member" "cloudrun_self_access" {
  service_account_id = data.google_service_account.cloudrun_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${data.google_service_account.cloudrun_sa.email}"
}

# Allow Cloud Build to act as the Cloud Run service account
resource "google_service_account_iam_member" "cloudbuild_access" {
  service_account_id = data.google_service_account.cloudrun_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

resource "google_cloud_run_v2_service" "api_service" {
  count    = var.skip_resource_creation ? 0 : 1
  name     = var.service_name
  location = local.region
  deletion_protection = false

  # This prevents errors when the service already exists
  lifecycle {
    ignore_changes = [template, traffic, annotations, labels]
    create_before_destroy = true
    # This will prevent recreation of the service, even if configurations change
    prevent_destroy = true
  }

  # Import the existing service on first apply
  # Use the following command to import it:
  # terraform import google_cloud_run_v2_service.api_service[0] projects/template-backend-dev-fddiferd/locations/us-central1/services/backend-rest-api

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
        name  = "PORT"
        value = "${var.api_port}"
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
        # Enable CPU boost for faster cold starts
        cpu_idle = false
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
    service_account = data.google_service_account.cloudrun_sa.email
  }
}

resource "google_cloud_run_service_iam_member" "public_access" {
  count    = var.skip_resource_creation ? 0 : 1
  location = var.skip_resource_creation ? local.region : google_cloud_run_v2_service.api_service[0].location
  project  = var.project_id
  service  = var.skip_resource_creation ? var.service_name : google_cloud_run_v2_service.api_service[0].name
  role     = "roles/run.invoker"
  member   = "allUsers"
  
  # depends_on cannot use conditional expressions
  depends_on = [
    google_cloud_run_v2_service.api_service
  ]
}

# For connecting GitHub to Cloud Build, follow these steps:
# 1. Go to: https://console.cloud.google.com/cloud-build/triggers/connect
# 2. Connect your GitHub repository
# 3. Follow the instructions to install the Cloud Build GitHub app
# 4. Then the triggers will work properly
# 
# This step cannot be fully automated with Terraform and requires manual setup once.

# Data source to check if GitHub is already connected
# This is best-effort - sometimes this won't be detectable from Terraform
# If GitHub connection issues persist, manually connect in the Google Cloud Console

# Development trigger (runs on push to any branch except main)
resource "google_cloudbuild_trigger" "dev_trigger" {
  count = (var.environment == "dev" && !var.skip_resource_creation) ? 1 : 0
  
  # Use a simple name pattern to avoid errors
  project  = var.project_id
  name     = "dev-branch-trigger" 
  description = "Build and deploy on any branch except main"
  
  # Use the YAML from the root directory
  filename = "cloudbuild.yaml"
  
  # Use included_files to only trigger when app code changes
  included_files = [
    "app/**",
    "docker/**", 
    "config",
    "cloudbuild.yaml",
    "pyproject.toml"
  ]
  
  # GitHub configuration - note this requires manual GitHub connection first
  # See: https://console.cloud.google.com/cloud-build/triggers/connect
  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      branch = "^(?!main$).*$"
    }
  }
  
  # Use explicit substitutions
  substitutions = {
    _SERVICE_NAME = var.service_name
    _REPO_NAME    = var.repo_name
    _REGION       = local.region
    _PROJECT_ENV  = var.environment
  }
  
  # Prevent creation issues by ignoring most attributes
  lifecycle {
    ignore_changes = [
      description,
      filename,
      github,
      included_files,
      substitutions,
      trigger_template,
      name
    ]
    create_before_destroy = true
  }
}

# Staging trigger (runs on push to main)
resource "google_cloudbuild_trigger" "staging_trigger" {
  count = (var.environment == "staging" && !var.skip_resource_creation) ? 1 : 0
  
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
    _PROJECT_ENV  = var.environment
  }
  
  # Prevent creation issues by ignoring most attributes
  lifecycle {
    ignore_changes = [
      description,
      filename,
      github,
      included_files,
      substitutions,
      trigger_template,
      name
    ]
    create_before_destroy = true
  }
}

# Production trigger (runs on tags starting with v)
resource "google_cloudbuild_trigger" "prod_trigger" {
  count = (var.environment == "prod" && !var.skip_resource_creation) ? 1 : 0
  
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
    _PROJECT_ENV  = var.environment
  }
  
  # Prevent creation issues by ignoring most attributes
  lifecycle {
    ignore_changes = [
      description,
      filename,
      github,
      included_files,
      substitutions,
      trigger_template,
      name
    ]
    create_before_destroy = true
  }
}
