#!/bin/bash

# Load environment variables
source .env

# Load configuration values
extract_config_value() {
    local key=$1
    local value
    value=$(grep "^$key: str = " config | sed -E "s/^$key: str = ['\"](.*)['\"].*$/\1/")
    echo "$value"
}

# Get repository and project information from config
REPO_NAME=$(extract_config_value "repo_name")
GITHUB_OWNER=$(extract_config_value "github_owner")
GCP_PROJECT_ID=$(extract_config_value "gcp_project_id")
REPO_URL="https://github.com/${GITHUB_OWNER}/${REPO_NAME}"

# Convert to lowercase for GCP naming
GCP_PROJECT_ID_LOWER=$(echo "$GCP_PROJECT_ID" | tr '[:upper:]' '[:lower:]')

# Create project IDs based on environment pattern
DEV_PROJECT_ID="${GCP_PROJECT_ID_LOWER}-dev"
STAGING_PROJECT_ID="${GCP_PROJECT_ID_LOWER}-staging"
PROD_PROJECT_ID="${GCP_PROJECT_ID_LOWER}-prod"

# Add developer suffix for dev environment if present
if [ -n "$DEV_SCHEMA_NAME" ]; then
    DEV_SCHEMA_LOWER=$(echo "$DEV_SCHEMA_NAME" | tr '[:upper:]' '[:lower:]')
    DEV_PROJECT_ID="${DEV_PROJECT_ID}-${DEV_SCHEMA_LOWER}"
fi

echo "Setting up Cloud Build triggers for repository: ${REPO_URL}"
echo "Using project IDs:"
echo "  Dev: $DEV_PROJECT_ID"
echo "  Staging: $STAGING_PROJECT_ID"
echo "  Prod: $PROD_PROJECT_ID"

echo "Creating Cloud Build trigger for master branch in production project..."
gcloud builds triggers create manual \
  --project=$PROD_PROJECT_ID \
  --name="deploy-master" \
  --build-config="cloudbuilds/cloudbuild-prod.yaml" \
  --repo="$REPO_URL" \
  --repo-type="GITHUB" \
  --branch="master"

echo "Creating Cloud Build trigger for staging branch in staging project..."
gcloud builds triggers create manual \
  --project=$STAGING_PROJECT_ID \
  --name="deploy-staging" \
  --build-config="cloudbuilds/cloudbuild-staging.yaml" \
  --repo="$REPO_URL" \
  --repo-type="GITHUB" \
  --branch="staging"

echo "Creating Cloud Build trigger for dev branch in development project..."
gcloud builds triggers create manual \
  --project=$DEV_PROJECT_ID \
  --name="deploy-dev" \
  --build-config="cloudbuilds/cloudbuild-dev.yaml" \
  --repo="$REPO_URL" \
  --repo-type="GITHUB" \
  --branch="dev"

echo "All triggers created successfully!"
echo ""
echo "Note: These are manual triggers that you can use to test deployments."
echo "To trigger a build, run:"
echo "gcloud builds triggers run deploy-master --branch=master --project=$PROD_PROJECT_ID"
echo "gcloud builds triggers run deploy-staging --branch=staging --project=$STAGING_PROJECT_ID"
echo "gcloud builds triggers run deploy-dev --branch=dev --project=$DEV_PROJECT_ID" 