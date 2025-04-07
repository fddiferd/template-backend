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
