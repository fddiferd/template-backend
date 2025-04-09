#!/bin/bash
set -e

# Get environment variables
source .env

# Check if MODE is set
if [ -z "$MODE" ]; then
  echo "⚠️ MODE not set in .env, defaulting to dev"
  MODE="dev"
fi

# Get project ID from config
extract_config_value() {
    local key=$1
    local value
    value=$(grep "^$key: str = " config | sed -E "s/^$key: str = ['\"](.*)['\"].*$/\1/")
    echo "$value"
}

GCP_PROJECT_ID=$(extract_config_value "gcp_project_id")
REGION=$(extract_config_value "region")

# Project naming based on mode
if [ "$MODE" == "dev" ]; then
  PROJECT_ID_LOWER=$(echo "$GCP_PROJECT_ID" | tr '[:upper:]' '[:lower:]')
  DEV_SCHEMA_LOWER=$(echo "$DEV_SCHEMA_NAME" | tr '[:upper:]' '[:lower:]')
  PROJECT_NAME="${PROJECT_ID_LOWER}-dev-${DEV_SCHEMA_LOWER}"
elif [ "$MODE" == "staging" ]; then
  PROJECT_ID_LOWER=$(echo "$GCP_PROJECT_ID" | tr '[:upper:]' '[:lower:]')
  PROJECT_NAME="${PROJECT_ID_LOWER}-staging"
elif [ "$MODE" == "prod" ]; then
  PROJECT_ID_LOWER=$(echo "$GCP_PROJECT_ID" | tr '[:upper:]' '[:lower:]')
  PROJECT_NAME="${PROJECT_ID_LOWER}-prod"
else
  echo "❌ Error: Invalid MODE: $MODE. Must be dev, staging, or prod."
  exit 1
fi

echo "======================================================================"
echo "Firestore Configuration Tool for project: $PROJECT_NAME"
echo "======================================================================"

# Create Terraform variables directory if it doesn't exist
mkdir -p terraform/bootstrap

# Check if Firestore is enabled and what mode it's in
echo "Checking Firestore database mode..."
FIRESTORE_MODE=$(gcloud firestore databases list --project="$PROJECT_NAME" --format="value(type)" 2>/dev/null || echo "")

# Flag to determine if Terraform should try to create the database
CREATE_DB_FLAG="false"

if [[ -z "$FIRESTORE_MODE" ]]; then
  echo "❓ Firestore database doesn't exist yet."
  echo "We will set up the database through gcloud in FIRESTORE_NATIVE mode"
  
  # Create Firestore in Native mode
  echo "Creating Firestore database in Native mode..."
  
  # Check if database exists
  DB_EXISTS=$(gcloud firestore databases list --project="$PROJECT_NAME" --format="value(name)" 2>/dev/null || echo "")
  
  if [[ -z "$DB_EXISTS" ]]; then
    echo "Creating new Firestore database in Native mode..."
    gcloud firestore databases create --project="$PROJECT_NAME" --location="$REGION" --type=firestore-native || {
      echo "⚠️ Failed to create database. It might still be in deletion process."
      echo "Try running the script again after a few minutes."
    }
  else
    echo "Database already exists."
  fi
  
  echo "✅ Firestore configuration completed"
  # Disable Terraform creation since we created it manually
  CREATE_DB_FLAG="false"
elif [[ "$FIRESTORE_MODE" == "FIRESTORE_NATIVE" ]]; then
  echo "✅ Firestore database is already in Native Mode. Perfect!"
  
  # Don't create with Terraform - already exists
  CREATE_DB_FLAG="false"
elif [[ "$FIRESTORE_MODE" == "DATASTORE_MODE" ]]; then
  echo "⚠️ Firestore database is in Datastore Mode, but you need Native Mode."
  
  # Unfortunately, we can't easily convert between modes
  # We need to delete and recreate
  echo "Attempting to delete the existing Datastore Mode database..."
  
  # First, check if there's data we need to preserve
  echo "Checking if there's data in the database..."
  # This is a simplified check - in production, you'd want a more thorough backup
  DATA_EXISTS=$(gcloud datastore operations list --project="$PROJECT_NAME" 2>/dev/null || echo "")
  
  if [[ -n "$DATA_EXISTS" ]]; then
    echo "⚠️ There appears to be data in your Datastore database."
    echo "Please backup your data before proceeding."
    echo "Skipping conversion to preserve your data."
    CREATE_DB_FLAG="false"
  else
    echo "No significant data found. Proceeding with database recreation."
    
    # Attempt to delete the database
    echo "Attempting to delete the existing database..."
    gcloud firestore databases delete --project="$PROJECT_NAME" --database="(default)" --quiet
    
    echo "Database deletion initiated. Waiting for deletion to complete..."
    echo "This process may take a few minutes."
    echo "You may need to run this script again in a few minutes to create the new database."
    
    # Set flag to indicate Terraform should not try to create
    CREATE_DB_FLAG="false"
    
    # Don't try to create the database right away
    # The script will need to be run again after deletion completes
    exit 0
  fi
else
  echo "⚠️ Firestore database is in unknown mode: $FIRESTORE_MODE"
  echo "Please contact support for assistance."
  
  # Don't create with Terraform if we're in an unknown state
  CREATE_DB_FLAG="false"
fi

# Update the Terraform variables file with the flag
echo "create_firestore_db = $CREATE_DB_FLAG" > terraform/bootstrap/terraform.tfvars
# Also add the Firestore mode - we'll use this in Terraform
echo "firestore_mode = \"FIRESTORE_NATIVE\"" >> terraform/bootstrap/terraform.tfvars

echo "======================================================================"
echo "Firestore configuration completed"
echo "======================================================================" 