#!/bin/bash
set -e

# Load environment variables
source .env

# Check if GCP_PROJECT_ID and GCP_BILLING_ACCOUNT_ID are set
if [ -z "$GCP_PROJECT_ID" ]; then
  echo "Error: GCP_PROJECT_ID is not set in .env"
  exit 1
fi

if [ -z "$GCP_BILLING_ACCOUNT_ID" ]; then
  echo "Error: GCP_BILLING_ACCOUNT_ID is not set in .env"
  exit 1
fi

if [ -z "$MODE" ]; then
  echo "MODE not set in .env, defaulting to dev"
  MODE="dev"
fi

# Project naming based on mode
if [ "$MODE" == "dev" ]; then
  PROJECT_NAME="${GCP_PROJECT_ID}-dev"
elif [ "$MODE" == "staging" ]; then
  PROJECT_NAME="${GCP_PROJECT_ID}-staging"
elif [ "$MODE" == "prod" ]; then
  PROJECT_NAME="${GCP_PROJECT_ID}"
else
  echo "Invalid MODE: $MODE. Must be dev, staging, or prod."
  exit 1
fi

echo "Checking if project $PROJECT_NAME exists..."

# Check if project exists
if gcloud projects describe "$PROJECT_NAME" &> /dev/null; then
  echo "Project $PROJECT_NAME already exists."
else
  echo "Creating project $PROJECT_NAME..."
  gcloud projects create "$PROJECT_NAME" --name="$PROJECT_NAME"
  
  echo "Linking billing account to project..."
  gcloud billing projects link "$PROJECT_NAME" --billing-account="$GCP_BILLING_ACCOUNT_ID"
fi

echo "Enabling required APIs..."
gcloud services enable --project="$PROJECT_NAME" \
  cloudresourcemanager.googleapis.com \
  firebase.googleapis.com \
  firestore.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  iam.googleapis.com \
  serviceusage.googleapis.com

echo "Setting up Terraform configuration..."
# Create terraform.tfvars file for bootstrap
mkdir -p terraform/bootstrap
cat > terraform/bootstrap/terraform.tfvars << EOF
environment = "$MODE"
billing_account_id = "$GCP_BILLING_ACCOUNT_ID"
project_ids = {
  $MODE = "$PROJECT_NAME"
}
EOF

# Initialize and apply Terraform
echo "Initializing Terraform..."
cd terraform/bootstrap
terraform init

echo "Applying Terraform bootstrap configuration..."
terraform apply -auto-approve

echo "Project setup complete!" 