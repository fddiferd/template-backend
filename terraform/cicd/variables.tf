variable "environment" {
  description = "The environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "service_name" {
  description = "The name of the Cloud Run service"
  type        = string
  default     = "fast-api"
}

variable "repo_name" {
  description = "The name of the Artifact Registry repository"
  type        = string
  default     = "fast-api"
}

variable "github_owner" {
  description = "The GitHub repository owner"
  type        = string
}

variable "github_repo" {
  description = "The GitHub repository name"
  type        = string
}

variable "user_email" {
  description = "The email of the user to grant permissions to"
  type        = string
}

variable "region" {
  description = "The region for GCP resources"
  type        = string
  default     = "us-central1"
}

variable "api_port" {
  description = "The port for the API container"
  type        = number
  default     = 8000
}

variable "api_host" {
  description = "The host for the API"
  type        = string
  default     = "0.0.0.0"
}

variable "cpu_limit" {
  description = "CPU limit for Cloud Run"
  type        = string
  default     = "1000m"
}

variable "memory_limit" {
  description = "Memory limit for Cloud Run"
  type        = string
  default     = "512Mi"
}

variable "min_instances" {
  description = "Minimum number of instances"
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum number of instances"
  type        = number
  default     = 3
}

variable "request_concurrency" {
  description = "Maximum number of concurrent requests per instance"
  type        = number
  default     = 80
}

variable "github_token" {
  description = "GitHub Personal Access Token for private repositories (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "skip_resource_creation" {
  description = "Set to true to skip creating resources that might already exist (helps avoid errors)"
  type        = bool
  default     = false
}
