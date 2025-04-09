output "cloud_run_url" {
  description = "The URL of the deployed Cloud Run service"
  value       = var.skip_resource_creation ? "https://${var.service_name}-${data.google_project.project.number}.${var.region}.run.app" : google_cloud_run_v2_service.api_service[0].uri
}
