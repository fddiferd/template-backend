# main.tf - Main Terraform configuration

# Load configuration from YAML
locals {
  config = yamldecode(file("${path.module}/../config.yaml"))
  project_name = local.config.project.name
  project_id = local.config.project.id
  region = local.config.project.region
  zone = local.config.project.zone
  env = var.environment
  developer = var.developer_name != "" ? var.developer_name : "shared"
  
  # Construct the actual project ID based on environment - include developer name for dev environment
  actual_project_id = local.env == "dev" ? "${local.project_id}-${local.env}-${local.developer}" : "${local.project_id}-${local.env}"
}

# Check if project already exists
data "google_projects" "existing_project" {
  filter = "projectId:${local.actual_project_id}"
}

locals {
  project_exists = length(data.google_projects.existing_project.projects) > 0
}

# Create the project only if it doesn't exist - but we should already have created it in the bootstrap script
resource "google_project" "project" {
  count = local.project_exists ? 0 : 1
  
  name            = "${local.project_name}-${upper(local.env)}"
  project_id      = local.actual_project_id
  billing_account = var.billing_account_id != "" ? var.billing_account_id : null
  auto_create_network = true
  
  lifecycle {
    # Ignore changes to these fields for existing projects
    ignore_changes = [
      billing_account,
      name,
      project_id,
      auto_create_network
    ]
    # Allow project to be modified or recreated
    prevent_destroy = false
  }
}

# Link billing account to project
resource "google_billing_project_info" "billing_link" {
  count = local.project_exists || var.billing_account_id == "" ? 0 : 1
  
  project         = local.actual_project_id 
  billing_account = var.billing_account_id
  depends_on      = [google_project.project]
  
  lifecycle {
    # Ignore changes to billing account for existing projects
    ignore_changes = [
      billing_account
    ]
    # Allow destroy since we handle billing in bootstrap script
    prevent_destroy = false
    create_before_destroy = true
  }
}

# Enable required Google APIs
resource "google_project_service" "services" {
  for_each = toset([
    "iam.googleapis.com",
    "cloudkms.googleapis.com",
    "firestore.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "compute.googleapis.com",
    "secretmanager.googleapis.com"
  ])
  
  project = local.actual_project_id
  service = each.value

  disable_dependent_services = true
  disable_on_destroy         = false
  
  # Use an empty static list as dependency to avoid errors
  depends_on = []
}

# Create a KMS key for bucket encryption
resource "google_kms_key_ring" "storage_keyring" {
  name     = "${local.project_name}-${local.env}-storage-keyring"
  location = local.region
  project  = local.actual_project_id
  depends_on = [google_project_service.services["cloudkms.googleapis.com"]]

  # Add lifecycle block to ignore failures on re-creation attempts
  lifecycle {
    ignore_changes = all
  }
}

resource "google_kms_crypto_key" "storage_key" {
  name            = "${local.project_name}-${local.env}-storage-key"
  key_ring        = google_kms_key_ring.storage_keyring.id
  rotation_period = "7776000s" # 90 days
}

# Grant the Cloud Storage service account access to use the KMS key
resource "google_kms_crypto_key_iam_binding" "crypto_key_binding" {
  crypto_key_id = google_kms_crypto_key.storage_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = []  # Empty initial list to avoid referring to service accounts that don't exist yet
  
  depends_on = [google_project_service.services["iam.googleapis.com"]]

  lifecycle {
    ignore_changes = [
      members,  # Ignore changes to members since we'll add them manually later
    ]
  }
}

# Create a custom Cloud Storage bucket for application assets
resource "google_storage_bucket" "app_assets" {
  name          = "${local.actual_project_id}-app-assets"
  location      = local.region
  project       = local.actual_project_id
  force_destroy = true

  uniform_bucket_level_access = true

  encryption {
    default_kms_key_name = google_kms_crypto_key.storage_key.id
  }

  depends_on = [google_kms_crypto_key_iam_binding.crypto_key_binding]

  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
} 