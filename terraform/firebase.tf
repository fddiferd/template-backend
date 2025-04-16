# Firebase setup for the project

# This module handles Firebase-specific configurations that aren't
# natively supported by Terraform Google provider

# First, make sure the Firebase API is enabled
resource "google_project_service" "firebase" {
  project            = var.project_id
  service            = "firebase.googleapis.com"
  disable_on_destroy = false
  
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [disable_on_destroy]
  }
}

# Enable Firestore API with graceful handling
resource "google_project_service" "firestore" {
  project            = var.project_id
  service            = "firestore.googleapis.com"
  disable_on_destroy = false
  
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [disable_on_destroy]
  }
  
  depends_on = [google_project_service.firebase]
}

# Use a null_resource to register the GCP project with Firebase
# This is necessary because there's no native Terraform resource for this
resource "null_resource" "firebase_project" {
  triggers = {
    project_id = var.project_id
  }
  
  # Use local-exec provisioner for Firebase setup
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      echo "Starting Firebase setup for project ${var.project_id}..."
      
      # Check if project is registered with Firebase already
      FIREBASE_CHECK=0
      if command -v firebase &> /dev/null; then
        echo "Checking Firebase registration via Firebase CLI..."
        if firebase projects:list --json 2>/dev/null | grep -q '"projectId":"${var.project_id}"'; then
          echo "Project is already registered with Firebase."
          FIREBASE_CHECK=1
        else
          echo "Project is not found in Firebase projects list."
        fi
      else
        echo "Firebase CLI not available, using alternative verification."
      fi
      
      # Check if Firestore exists (indirect verification of Firebase setup)
      echo "Checking if Firestore database exists..."
      if gcloud firestore databases list --project="${var.project_id}" 2>/dev/null | grep -q '(default)'; then
        echo "Firestore database exists, project likely registered with Firebase."
        FIREBASE_CHECK=1
      else
        echo "Firestore database not found."
      fi
      
      # Only attempt to register if not already registered
      if [ "$FIREBASE_CHECK" -eq 0 ]; then
        echo "Attempting to register project with Firebase..."
        
        # Get current user
        USER_EMAIL=$(gcloud config get-value account 2>/dev/null)
        echo "Current user: $USER_EMAIL"
        
        # Add Firebase Admin role to current user if needed
        echo "Adding Firebase Admin role to current user..."
        gcloud projects add-iam-policy-binding "${var.project_id}" \
          --member="user:$USER_EMAIL" \
          --role="roles/firebase.admin" --quiet 2>/dev/null || \
          echo "Warning: Could not add Firebase Admin role. You may not have sufficient permissions."
        
        # Try multiple methods to add project to Firebase
        if command -v firebase &> /dev/null; then
          echo "Attempting to add project using Firebase CLI..."
          firebase projects:addfirebase "${var.project_id}" 2>/dev/null || \
            echo "Warning: Failed to add project via Firebase CLI."
        fi
        
        echo "Attempting to add project using gcloud commands..."
        gcloud alpha firebase projects add "${var.project_id}" 2>/dev/null || \
        gcloud firebase projects:addfirebase "${var.project_id}" 2>/dev/null || \
          echo "Warning: Failed to add project via gcloud. Manual action may be required."
        
        echo "Firebase registration attempts completed."
      fi
    EOT
  }
  
  depends_on = [google_project_service.firebase, google_project_service.firestore]
}

# Create Firestore database
resource "null_resource" "firestore_database" {
  triggers = {
    project_id = var.project_id
  }
  
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      echo "Setting up Firestore database for project ${var.project_id}..."
      
      # Check if Firestore database exists
      if gcloud firestore databases list --project="${var.project_id}" 2>/dev/null | grep -q '(default)'; then
        echo "Firestore database already exists. Skipping creation."
      else
        echo "Creating Firestore database in Native mode..."
        gcloud firestore databases create --location=nam5 --project="${var.project_id}" 2>/dev/null || \
          echo "Warning: Failed to create Firestore database. Manual action may be required."
      fi
    EOT
  }
  
  depends_on = [null_resource.firebase_project]
}

# Set up Firebase service account
resource "google_service_account" "firebase_admin" {
  account_id   = "firebase-admin"
  display_name = "Firebase Admin Service Account"
  description  = "Service account for Firebase Admin SDK"
  project      = var.project_id
}

# Add Firebase Admin role to the service account
resource "google_project_iam_member" "firebase_admin_role" {
  project = var.project_id
  role    = "roles/firebase.admin"
  member  = "serviceAccount:${google_service_account.firebase_admin.email}"
}

# Add Firestore Admin role to the service account
resource "google_project_iam_member" "firestore_admin_role" {
  project = var.project_id
  role    = "roles/firestore.admin"
  member  = "serviceAccount:${google_service_account.firebase_admin.email}"
}

# Add Datastore User role to the service account
resource "google_project_iam_member" "datastore_user_role" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.firebase_admin.email}"
}

# Add Secret Manager Secret Accessor role to the service account
resource "google_project_iam_member" "secret_accessor_role" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.firebase_admin.email}"
}

# Create service account key and store in Secret Manager
resource "null_resource" "firebase_service_account_key" {
  triggers = {
    service_account_email = google_service_account.firebase_admin.email
  }
  
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      echo "Creating Firebase Admin service account key..."
      
      # Create secrets directory if it doesn't exist
      mkdir -p secrets
      
      # Generate service account key
      KEY_FILE="secrets/firebase-admin-key.json"
      if gcloud iam service-accounts keys create "$KEY_FILE" \
        --iam-account="${google_service_account.firebase_admin.email}" \
        --project="${var.project_id}" 2>/dev/null; then
        echo "Service account key generated successfully."
        chmod 600 "$KEY_FILE"
        
        # Check if secret already exists
        if gcloud secrets describe firebase-credentials --project="${var.project_id}" &>/dev/null; then
          echo "Secret already exists. Adding new version..."
          gcloud secrets versions add firebase-credentials \
            --data-file="$KEY_FILE" \
            --project="${var.project_id}" 2>/dev/null || \
            echo "Warning: Failed to add new version to secret."
        else
          echo "Creating new secret..."
          gcloud secrets create firebase-credentials \
            --data-file="$KEY_FILE" \
            --project="${var.project_id}" 2>/dev/null || \
            echo "Warning: Failed to create secret."
        fi
      else
        echo "Warning: Failed to create service account key. Manual action may be required."
      fi
    EOT
  }
  
  depends_on = [
    google_service_account.firebase_admin,
    google_project_iam_member.firebase_admin_role,
    google_project_iam_member.firestore_admin_role,
    google_project_iam_member.datastore_user_role,
    google_project_iam_member.secret_accessor_role
  ]
}

# Create sample data in Firestore for development environment
resource "null_resource" "sample_firestore_data" {
  count = var.environment == "dev" ? 1 : 0
  
  triggers = {
    project_id = var.project_id
  }
  
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      echo "Creating sample data in Firestore for development environment..."
      
      # Check if service account key exists
      KEY_FILE="secrets/firebase-admin-key.json"
      if [ ! -f "$KEY_FILE" ]; then
        echo "Service account key not found. Skipping sample data creation."
        exit 0
      fi
      
      # Create sample data if needed
      # This is a placeholder - you would add actual data creation commands here
      echo "Sample Firestore data creation finished."
    EOT
  }
  
  depends_on = [null_resource.firebase_service_account_key, null_resource.firestore_database]
} 
