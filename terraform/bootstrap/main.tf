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
  project = "wedge-golf-${var.environment}"
  region  = "us-central1"
}

provider "google-beta" {
  project = "wedge-golf-${var.environment}"
  region  = "us-central1"
}

# Enable billing for each project
resource "google_billing_project_info" "billing" {
  for_each = var.project_ids

  project         = each.value
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
resource "google_project_iam_member" "firebase_admin_permissions" {
  for_each = var.project_ids

  project = each.value
  role    = "roles/serviceusage.serviceUsageAdmin"
  member  = "serviceAccount:firebase-adminsdk-fbsvc@${each.value}.iam.gserviceaccount.com"
}

# Additional Firebase Admin permissions
resource "google_project_iam_member" "firebase_admin_auth" {
  for_each = var.project_ids

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
      "artifactregistry.googleapis.com"
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

# Create Artifact Registry repositories
resource "google_artifact_registry_repository" "wedge_api" {
  for_each = var.project_ids

  provider = google-beta
  project  = each.value
  location = "us-central1"
  
  repository_id = "wedge-api"
  description   = "Docker repository for Wedge API"
  format        = "DOCKER"

  depends_on = [google_project_service.required_apis]
}

# Grant permissions to push/pull images
resource "google_artifact_registry_repository_iam_member" "ci_cd_access" {
  for_each = var.project_ids

  provider   = google-beta
  project    = each.value
  location   = google_artifact_registry_repository.wedge_api[each.key].location
  repository = google_artifact_registry_repository.wedge_api[each.key].name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${each.value}@cloudbuild.gserviceaccount.com"
}

# Grant permissions to Cloud Run to pull images
resource "google_artifact_registry_repository_iam_member" "cloud_run_access" {
  for_each = var.project_ids

  provider   = google-beta
  project    = each.value
  location   = google_artifact_registry_repository.wedge_api[each.key].location
  repository = google_artifact_registry_repository.wedge_api[each.key].name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:service-${data.google_project.project[each.key].number}@serverless-robot-prod.iam.gserviceaccount.com"

  depends_on = [google_project_service.required_apis]
}

# Get project information for service account email
data "google_project" "project" {
  for_each = var.project_ids
  
  project_id = each.value
}
