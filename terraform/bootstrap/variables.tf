variable "project_ids" {
  type = map(string)
}

variable "credentials_file" {
  type = string
  default = "../../firebase-dev.json"
}

variable "environment" {
  description = "The environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

variable "billing_account_id" {
  description = "The ID of the billing account to associate with the projects"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "The region for GCP resources"
  type        = string
  default     = "us-central1"
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
