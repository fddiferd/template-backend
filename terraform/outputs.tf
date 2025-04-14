output "project_id" {
  description = "Google Cloud Project ID"
  value       = local.actual_project_id
}

output "project_number" {
  description = "Google Cloud Project Number"
  value       = local.project_exists ? try([for p in data.google_projects.existing_project.projects : p.number if p.project_id == local.actual_project_id][0], "") : try(google_project.project[0].number, "")
}

output "backend_url" {
  description = "URL of the deployed backend service"
  value       = try(google_cloud_run_service.backend.status[0].url, "")
}

output "frontend_url" {
  description = "URL of the deployed frontend service"
  value       = try(google_cloud_run_service.frontend.status[0].url, "")
}

output "app_storage_bucket" {
  description = "Storage bucket name"
  value       = try(google_storage_bucket.app_assets.name, "")
}

output "firestore_database" {
  description = "Firestore Database ID"
  value       = try(google_firestore_database.database.name, "")
}

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}

output "region" {
  description = "GCP Region"
  value       = local.region
}

output "cloud_run_url" {
  value       = try(google_cloud_run_v2_service.fastapi.uri, "")
  description = "The URL of the deployed Cloud Run service"
}

output "service_account_email" {
  value       = try(google_service_account.cloud_run_service_account.email, "")
  description = "The email of the service account used by the Cloud Run service"
}

output "firebase_admin_email" {
  value       = try(google_service_account.firebase_admin.email, "")
  description = "The email of the Firebase admin service account"
} 