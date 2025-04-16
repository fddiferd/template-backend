# service_accounts.tf - Define service accounts and their permissions

# Create the service accounts if they don't exist
resource "google_service_account" "cloud_run_service_account" {
  project      = local.actual_project_id
  account_id   = var.service_account_name
  display_name = "Cloud Run Service Account"
  description  = "Service account for Cloud Run services"
  
  lifecycle {
    ignore_changes = all
  }
}

resource "google_service_account" "backend_service_account" {
  project      = local.actual_project_id
  account_id   = "backend-sa"
  display_name = "Backend Service Account"
  
  lifecycle {
    ignore_changes = all
  }
}

resource "google_service_account" "frontend_service_account" {
  project      = local.actual_project_id
  account_id   = "frontend-sa"
  display_name = "Frontend Service Account"
  
  lifecycle {
    ignore_changes = all
  }
}

resource "google_service_account" "firebase_admin" {
  project      = local.actual_project_id
  account_id   = "firebase-admin"
  display_name = "Firebase Admin Service Account"
  description  = "Service account for Firebase Admin SDK"
  
  lifecycle {
    ignore_changes = all  # Prevent recreation attempts
  }
}

# Grant permissions to service accounts
resource "google_project_iam_member" "cloud_run_firestore_access" {
  project = local.actual_project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.cloud_run_service_account.email}"
  
  lifecycle {
    ignore_changes = all
  }
}

resource "google_project_iam_member" "cloud_run_firestore_owner" {
  project = local.actual_project_id
  role    = "roles/datastore.owner"
  member  = "serviceAccount:${google_service_account.cloud_run_service_account.email}"
  
  lifecycle {
    ignore_changes = all
  }
}

resource "google_project_iam_member" "cloud_run_firebase_admin" {
  project = local.actual_project_id
  role    = "roles/firebase.admin"
  member  = "serviceAccount:${google_service_account.cloud_run_service_account.email}"
  
  lifecycle {
    ignore_changes = all
  }
}

resource "google_project_iam_member" "cloud_run_firebase_developer" {
  project = local.actual_project_id
  role    = "roles/firebase.developAdmin"
  member  = "serviceAccount:${google_service_account.cloud_run_service_account.email}"
  
  lifecycle {
    ignore_changes = all
  }
}

resource "google_project_iam_member" "backend_firestore_access" {
  project = local.actual_project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.backend_service_account.email}"
  
  lifecycle {
    ignore_changes = all
  }
}

resource "google_project_iam_member" "firebase_admin_firestore" {
  project = local.actual_project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.firebase_admin.email}"
  
  lifecycle {
    ignore_changes = all
  }
}

resource "google_project_iam_member" "firebase_admin_developer" {
  project = local.actual_project_id
  role    = "roles/firebase.developAdmin"
  member  = "serviceAccount:${google_service_account.firebase_admin.email}"
  
  lifecycle {
    ignore_changes = all
  }
}

resource "google_project_iam_member" "firebase_admin_admin" {
  project = local.actual_project_id
  role    = "roles/firebase.admin"
  member  = "serviceAccount:${google_service_account.firebase_admin.email}"
  
  lifecycle {
    ignore_changes = all
  }
}

resource "google_project_iam_member" "firebase_admin_viewer" {
  project = local.actual_project_id
  role    = "roles/firebase.viewer"
  member  = "serviceAccount:${google_service_account.firebase_admin.email}"
  
  lifecycle {
    ignore_changes = all
  }
}

resource "google_project_iam_member" "firestore_owner" {
  project = local.actual_project_id
  role    = "roles/datastore.owner"
  member  = "serviceAccount:${google_service_account.firebase_admin.email}"
  
  lifecycle {
    ignore_changes = all
  }
}

# Create a key for Firebase admin service account
resource "google_service_account_key" "firebase_key" {
  service_account_id = google_service_account.firebase_admin.name
  
  lifecycle {
    ignore_changes = all  # Prevent recreation attempts
    create_before_destroy = true  # Create new key before destroying old one
  }
} 