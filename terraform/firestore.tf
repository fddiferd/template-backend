resource "google_project_service" "firestore" {
  project = local.actual_project_id
  service = "firestore.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = false
  
  depends_on = []
}

# Enable Firebase API
resource "google_project_service" "firebase" {
  project = local.actual_project_id
  service = "firebase.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = false
  
  depends_on = []
}

resource "google_firestore_database" "database" {
  project     = local.actual_project_id
  name        = "(default)"
  location_id = "us-central1"
  type        = "FIRESTORE_NATIVE"

  depends_on = [google_project_service.services["firestore.googleapis.com"]]
  
  lifecycle {
    ignore_changes = all
  }
}

# Output the key for use in the FastAPI application
output "firebase_key" {
  value     = google_service_account_key.firebase_key.private_key
  sensitive = true
}

# Create collections (optional, usually done by application)
# These are examples of collections that could be created
resource "google_firestore_document" "customers_collection" {
  count        = var.environment == "dev" ? 1 : 0
  project      = local.actual_project_id
  collection   = "customers"
  document_id  = "sample"
  fields       = jsonencode({
    email = {
      stringValue = "sample@example.com"
    }
    name = {
      stringValue = "Sample Customer"
    }
    created_at = {
      timestampValue = "${timestamp()}"
    }
  })
  
  depends_on = [google_firestore_database.database]
}

resource "google_firestore_document" "items_collection" {
  count        = var.environment == "dev" ? 1 : 0
  project      = local.actual_project_id
  collection   = "items"
  document_id  = "sample"
  fields       = jsonencode({
    name = {
      stringValue = "Sample Item"
    }
    price = {
      doubleValue = 19.99
    }
    description = {
      stringValue = "This is a sample item for testing"
    }
    created_at = {
      timestampValue = "${timestamp()}"
    }
  })
  
  depends_on = [google_firestore_database.database]
} 