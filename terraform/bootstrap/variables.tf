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

variable "firebase_initialized" {
  description = "Map of project keys to booleans indicating if Firebase is initialized"
  type        = map(bool)
  default     = {}
}

variable "create_firestore_db" {
  description = "Flag to determine if Firestore database should be created by Terraform"
  type        = bool
  default     = false
}

variable "firestore_mode" {
  description = "The mode for Firestore database (FIRESTORE_NATIVE or DATASTORE_MODE)"
  type        = string
  default     = "FIRESTORE_NATIVE"
}

variable "skip_billing_setup" {
  description = "Flag to skip billing setup and other operations that are only needed for new projects"
  type        = bool
  default     = false
}
