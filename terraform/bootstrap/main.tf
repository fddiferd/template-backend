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

# Get the first project ID from the map
locals {
  first_project_id = values(var.project_ids)[0]
  region = var.region
  firebase_initialized = var.firebase_initialized
}

provider "google" {
  project = local.first_project_id
  region  = local.region
}

provider "google-beta" {
  project = local.first_project_id
  region  = local.region
}

# Enable billing for each project
resource "google_billing_project_info" "billing" {
  for_each = var.skip_billing_setup ? {} : var.project_ids
  
  project_id     = each.value
  billing_account = var.billing_account_id
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

  disable_dependent_services = false
  disable_on_destroy        = false
}

# Grant necessary permissions to Firebase Admin service accounts
# Only create this for projects with Firebase initialized
resource "google_project_iam_member" "firebase_admin_permissions" {
  for_each = {
    for k, v in var.project_ids : k => v
    if lookup(local.firebase_initialized, k, false)
  }
  
  project = each.value
  role    = "roles/serviceusage.serviceUsageAdmin"
  member  = "serviceAccount:firebase-adminsdk-fbsvc@${each.value}.iam.gserviceaccount.com"
}

# Additional Firebase Admin permissions
resource "google_project_iam_member" "firebase_admin_auth" {
  # Only create this for projects with Firebase initialized
  for_each = {
    for k, v in var.project_ids : k => v
    if lookup(local.firebase_initialized, k, false)
  }
  
  project = each.value
  role    = "roles/firebaseauth.admin"
  member  = "serviceAccount:firebase-adminsdk-fbsvc@${each.value}.iam.gserviceaccount.com"
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = {
    for pair in setproduct(keys(var.project_ids), [
      "firebase.googleapis.com",
      "firestore.googleapis.com",
      "cloudresourcemanager.googleapis.com",
      "serviceusage.googleapis.com",
      "artifactregistry.googleapis.com",
      "cloudbuild.googleapis.com"
    ]) : "${pair[0]}-${pair[1]}" => {
      project = var.project_ids[pair[0]]
      api     = pair[1]
    }
  }

  project = each.value.project
  service = each.value.api

  disable_dependent_services = false
  disable_on_destroy        = false
}

# Try to check for existing Artifact Registry repository
data "google_artifact_registry_repository" "existing_repo" {
  for_each = var.project_ids
  
  location      = local.region
  repository_id = var.repo_name
  project       = each.value
}

# Create Artifact Registry repositories only if they don't exist yet
resource "google_artifact_registry_repository" "api_repo" {
  for_each = {
    for k, v in var.project_ids : k => v
    if !can(data.google_artifact_registry_repository.existing_repo[k])
  }

  provider = google-beta
  project  = each.value
  location = local.region
  
  repository_id = var.repo_name
  description   = "Docker repository for ${var.service_name}"
  format        = "DOCKER"

  depends_on = [google_project_service.required_apis]
  
  # This lifecycle block helps handle existing repositories
  lifecycle {
    ignore_changes = [
      description, 
      format,
      repository_id
    ]
    prevent_destroy = true
  }
}

# Enable Cloud Build service account
resource "google_project_service_identity" "cloudbuild" {
  for_each = var.project_ids
  
  provider = google-beta
  project  = each.value
  service  = "cloudbuild.googleapis.com"

  depends_on = [google_project_service.required_apis]
}

# Grant permissions to push/pull images
resource "google_artifact_registry_repository_iam_member" "ci_cd_access" {
  for_each = var.project_ids

  provider   = google-beta
  project    = each.value
  location   = local.region
  repository = var.repo_name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_project_service_identity.cloudbuild[each.key].email}"

  depends_on = [google_project_service_identity.cloudbuild]
}

# Grant permissions to Cloud Run to pull images
resource "google_artifact_registry_repository_iam_member" "cloud_run_access" {
  for_each = var.project_ids

  provider   = google-beta
  project    = each.value
  location   = local.region
  repository = var.repo_name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:service-${data.google_project.project[each.key].number}@serverless-robot-prod.iam.gserviceaccount.com"

  depends_on = [google_project_service.required_apis]
}

# Get project information for service account email
data "google_project" "project" {
  for_each = var.project_ids
  
  project_id = each.value
}

# Initialize Firestore database - using Native Mode
# Use conditional creation to avoid errors with existing databases
resource "google_firestore_database" "database" {
  for_each = {
    for k, v in var.project_ids : k => v
    # Only create if not found in existing list (checked in the bootstrap.sh script)
    if var.create_firestore_db
  }
  
  project     = each.value
  name        = "(default)"
  location_id = local.region
  type        = var.firestore_mode  # Use the variable set by firestore_setup.sh
  
  # Better handling for database that might have been created manually
  # or is in a different mode
  lifecycle {
    prevent_destroy = true
    # If database was already created in a different mode, we'll ignore it
    ignore_changes = [location_id, type, concurrency_mode, app_engine_integration_mode]
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_firebase_project.default
  ]
}
