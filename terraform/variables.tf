variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "environment" {
  description = "Environment to deploy (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "developer_name" {
  description = "Developer name for dev environment (will be appended to project ID)"
  type        = string
  default     = ""
}

variable "billing_account_id" {
  description = "The ID of the billing account to associate with the project"
  type        = string
  
  validation {
    condition     = length(var.billing_account_id) > 0
    error_message = "Billing account ID must be provided."
  }
}

variable "region" {
  description = "The GCP region to deploy resources"
  type        = string
  default     = "us-central1"
}

variable "app_name" {
  description = "Name of the FastAPI application"
  type        = string
  default     = "fastapi-backend"
}

variable "image" {
  description = "Docker image URL for the FastAPI application"
  type        = string
  default     = "gcr.io/PROJECT_ID/fastapi-app:latest"
}

variable "database_name" {
  description = "Firebase/Firestore database name"
  type        = string
  default     = "app-database"
}

variable "service_account_name" {
  description = "Service account for the Cloud Run service"
  type        = string
  default     = "fastapi-service-account"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "firestore_location" {
  description = "The location for the Firestore database"
  type        = string
  default     = "us-central"
}

# Cloud Run service configuration
variable "backend_service_name" {
  description = "Name of the backend Cloud Run service"
  type        = string
  default     = "backend-api"
}

variable "frontend_service_name" {
  description = "Name of the frontend Cloud Run service"
  type        = string
  default     = "frontend-web"
}

variable "backend_container_image" {
  description = "Container image for the backend service"
  type        = string
  default     = "backend:latest"
}

variable "frontend_container_image" {
  description = "Container image for the frontend service"
  type        = string
  default     = "frontend:latest"
}

variable "backend_container_port" {
  description = "Port the backend container listens on"
  type        = number
  default     = 8080
}

variable "frontend_container_port" {
  description = "Port the frontend container listens on"
  type        = number
  default     = 3000
}

variable "min_instances" {
  description = "Minimum number of instances for Cloud Run"
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum number of instances for Cloud Run"
  type        = number
  default     = 10
}

variable "memory" {
  description = "Memory allocated to each instance"
  type        = string
  default     = "512Mi"
}

variable "cpu" {
  description = "CPU allocated to each instance"
  type        = string
  default     = "1"
} 