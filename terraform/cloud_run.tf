resource "google_project_service" "run" {
  project = local.actual_project_id
  service = "run.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = false
  
  depends_on = []
}

resource "google_project_service" "artifact_registry" {
  project = local.actual_project_id
  service = "artifactregistry.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = false
  
  depends_on = []
}

# Create the Cloud Run service
resource "google_cloud_run_v2_service" "fastapi" {
  name     = var.app_name
  location = var.region
  project  = local.actual_project_id
  
  depends_on = [
    google_project_service.run,
    google_service_account.cloud_run_service_account
  ]

  template {
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = var.image
      
      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }
      
      ports {
        container_port = var.container_port
      }

      # Environment variables for Firebase configuration
      env {
        name  = "FIREBASE_PROJECT_ID"
        value = local.actual_project_id
      }
      
      # Mount Firebase credentials as a volume
      volume_mounts {
        name       = "firebase-key"
        mount_path = "/secrets"
      }
    }
    
    volumes {
      name = "firebase-key"
      secret {
        secret = google_secret_manager_secret.firebase_credentials.secret_id
        items {
          version = "latest"
          path    = "firebase-credentials.json"
        }
      }
    }

    # Use service account from this project
    service_account = "${var.service_account_name}@${local.actual_project_id}.iam.gserviceaccount.com"
  }
}

# Create a Secret Manager secret for Firebase credentials
resource "google_secret_manager_secret" "firebase_credentials" {
  secret_id = "firebase-credentials"
  project   = local.actual_project_id
  
  replication {
    auto {}
  }
  
  depends_on = [google_project_service.services["secretmanager.googleapis.com"]]
}

# Store Firebase credentials in Secret Manager
resource "google_secret_manager_secret_version" "firebase_credentials_version" {
  secret      = google_secret_manager_secret.firebase_credentials.id
  secret_data = "{}" # Placeholder to be replaced later
  
  lifecycle {
    ignore_changes = [
      secret_data,
    ]
  }

  depends_on = [google_secret_manager_secret.firebase_credentials]
}

# Allow Cloud Run service to access the secret
resource "google_secret_manager_secret_iam_member" "cloud_run_secret_access" {
  project   = local.actual_project_id
  secret_id = google_secret_manager_secret.firebase_credentials.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run_service_account.email}"
}

# Make the Cloud Run service publicly accessible
resource "google_cloud_run_service_iam_member" "public_access" {
  location = google_cloud_run_v2_service.fastapi.location
  service  = google_cloud_run_v2_service.fastapi.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Backend Service
resource "google_cloud_run_service" "backend" {
  name     = var.backend_service_name
  location = local.region
  project  = local.actual_project_id

  template {
    spec {
      containers {
        image = var.backend_container_image
        
        ports {
          container_port = var.backend_container_port
        }
        
        resources {
          limits = {
            cpu    = local.config.environments[local.env].resources.cpu
            memory = local.config.environments[local.env].resources.memory
          }
        }
        
        env {
          name  = "ENVIRONMENT"
          value = local.env
        }
        
        env {
          name  = "GCP_PROJECT_ID"
          value = local.actual_project_id
        }
        
        # Mount Firebase credentials as a volume
        volume_mounts {
          name       = "firebase-credentials"
          mount_path = "/secrets"
        }
      }
      
      # Define the volume for Firebase credentials
      volumes {
        name = "firebase-credentials"
        secret {
          secret_name = google_secret_manager_secret.firebase_credentials.secret_id
          items {
            key  = "latest"
            path = "firebase-credentials.json"
          }
        }
      }
      
      # Use service account from this project
      service_account_name = "backend-sa@${local.actual_project_id}.iam.gserviceaccount.com"
    }
    
    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale" = local.config.environments[local.env].resources.min_instances
        "autoscaling.knative.dev/maxScale" = local.config.environments[local.env].resources.max_instances
      }
    }
  }
  
  traffic {
    percent         = 100
    latest_revision = true
  }
  
  depends_on = [
    google_project_service.services["run.googleapis.com"],
    google_secret_manager_secret_version.firebase_credentials_version,
    google_service_account.backend_service_account
  ]
}

# Frontend Service
resource "google_cloud_run_service" "frontend" {
  name     = var.frontend_service_name
  location = local.region
  project  = local.actual_project_id

  template {
    spec {
      containers {
        image = var.frontend_container_image
        
        ports {
          container_port = var.frontend_container_port
        }
        
        resources {
          limits = {
            cpu    = local.config.environments[local.env].resources.cpu
            memory = local.config.environments[local.env].resources.memory
          }
        }
        
        env {
          name  = "NODE_ENV"
          value = local.env == "prod" ? "production" : local.env == "staging" ? "staging" : "development"
        }
        
        env {
          name  = "BACKEND_URL"
          value = google_cloud_run_service.backend.status[0].url
        }
      }
      
      # Use service account from this project
      service_account_name = "frontend-sa@${local.actual_project_id}.iam.gserviceaccount.com"
    }
    
    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale" = local.config.environments[local.env].resources.min_instances
        "autoscaling.knative.dev/maxScale" = local.config.environments[local.env].resources.max_instances
      }
    }
  }
  
  traffic {
    percent         = 100
    latest_revision = true
  }
  
  depends_on = [
    google_project_service.services["run.googleapis.com"],
    google_cloud_run_service.backend,
    google_service_account.frontend_service_account
  ]
}

# Allow unauthenticated access to both services
resource "google_cloud_run_service_iam_member" "backend_public_access" {
  location = google_cloud_run_service.backend.location
  project  = local.actual_project_id
  service  = google_cloud_run_service.backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
  
  lifecycle {
    ignore_changes = all
  }
}

resource "google_cloud_run_service_iam_member" "frontend_public_access" {
  location = google_cloud_run_service.frontend.location
  project  = local.actual_project_id
  service  = google_cloud_run_service.frontend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
  
  lifecycle {
    ignore_changes = all
  }
} 