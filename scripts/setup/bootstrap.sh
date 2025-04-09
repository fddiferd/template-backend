#!/bin/bash
set -e

echo "===================================================================="
echo "            GCP Project Bootstrap Tool                               "
echo "===================================================================="

#==========================================================================
# SECTION 1: CONFIGURATION LOADING
#==========================================================================
echo
echo "LOADING CONFIGURATION"
echo "---------------------"

# Load environment variables
echo "Loading environment variables..."
source .env

# Load config values using a more portable approach for macOS
echo "Loading project configuration..."

# Function to extract values from config file (macOS compatible)
extract_config_value() {
    local key=$1
    local value
    value=$(grep "^$key: str = " config | sed -E "s/^$key: str = ['\"](.*)['\"].*$/\1/")
    echo "$value"
}

GCP_PROJECT_ID=$(extract_config_value "gcp_project_id")
SERVICE_NAME=$(extract_config_value "service_name")
REPO_NAME=$(extract_config_value "repo_name")
REGION=$(extract_config_value "region")

# Check if PROJECT_ID from config is available
if [ -z "$GCP_PROJECT_ID" ]; then
  echo "❌ Error: gcp_project_id is not set in config file"
  exit 1
fi

# Use PROJECT_ID from .env if specified, otherwise use from config
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID="$GCP_PROJECT_ID"
fi

if [ -z "$GCP_BILLING_ACCOUNT_ID" ]; then
  echo "❌ Error: GCP_BILLING_ACCOUNT_ID is not set in .env"
  exit 1
fi

if [ -z "$MODE" ]; then
  echo "⚠️ MODE not set in .env, defaulting to dev"
  MODE="dev"
fi

if [ "$MODE" == "dev" ] && [ -z "$DEV_SCHEMA_NAME" ]; then
  echo "❌ Error: DEV_SCHEMA_NAME not set in .env, required for dev mode"
  exit 1
fi

#==========================================================================
# SECTION 2: PROJECT SETUP
#==========================================================================
echo
echo "PROJECT SETUP"
echo "-------------"

# Project naming based on mode
if [ "$MODE" == "dev" ]; then
  PROJECT_NAME="${PROJECT_ID,,}-dev_${DEV_SCHEMA_NAME,,}"
elif [ "$MODE" == "staging" ]; then
  PROJECT_NAME="${PROJECT_ID,,}-staging"
elif [ "$MODE" == "prod" ]; then
  PROJECT_NAME="${PROJECT_ID,,}-prod"
else
  echo "❌ Error: Invalid MODE: $MODE. Must be dev, staging, or prod."
  exit 1
fi

echo "Bootstrapping project: $PROJECT_NAME (Environment: $MODE)"

echo "Checking if project $PROJECT_NAME exists..."

# Check if project exists
if gcloud projects describe "$PROJECT_NAME" &> /dev/null; then
  echo "✅ Project $PROJECT_NAME already exists."
  
  # Check permissions
  echo "Checking permissions..."
  if gcloud projects get-iam-policy "$PROJECT_NAME" &> /dev/null; then
    echo "✅ You have sufficient permissions on this project."
  else
    echo "❌ Error: You don't have sufficient permissions on this project."
    exit 1
  fi
else
  echo "Project doesn't exist. Checking billing account..."
  
  # Check if billing account exists and we have access to it
  if gcloud billing accounts list --filter="ACCOUNT_ID:$GCP_BILLING_ACCOUNT_ID" --format="value(ACCOUNT_ID)" | grep -q "$GCP_BILLING_ACCOUNT_ID"; then
    echo "✅ Billing account exists. Creating project $PROJECT_NAME..."
    gcloud projects create "$PROJECT_NAME" --name="$PROJECT_NAME"
    
    echo "Linking billing account to project..."
    gcloud billing projects link "$PROJECT_NAME" --billing-account="$GCP_BILLING_ACCOUNT_ID"
  else
    echo "❌ Error: Could not access billing account $GCP_BILLING_ACCOUNT_ID"
    echo "This could be due to:"
    echo "  1. The billing account ID is incorrect"
    echo "  2. You need to authenticate with sufficient permissions"
    echo ""
    echo "Try running: gcloud auth login"
    echo "Then verify you have access with: gcloud billing accounts list"
    exit 1
  fi
fi

#==========================================================================
# SECTION 3: API ENABLEMENT
#==========================================================================
echo
echo "ENABLING APIS"
echo "-------------"

echo "Enabling required APIs for $PROJECT_NAME..."
gcloud services enable --project="$PROJECT_NAME" \
  cloudresourcemanager.googleapis.com \
  firebase.googleapis.com \
  firestore.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  iam.googleapis.com \
  serviceusage.googleapis.com

echo "✅ APIs enabled successfully"

#==========================================================================
# SECTION 4: TERRAFORM CONFIGURATION
#==========================================================================
echo
echo "TERRAFORM CONFIGURATION"
echo "-----------------------"

# Get GitHub repository information for Terraform
REPO_OWNER=$(git config --get remote.origin.url | sed -e 's/.*github.com[:/]\([^/]*\).*/\1/')
REPO_NAME=$(basename -s .git $(git config --get remote.origin.url))
USER_EMAIL=$(git config --get user.email)

# Prepare Terraform variables
echo "Setting up Terraform configuration..."

# Create terraform.tfvars file for bootstrap
mkdir -p terraform/bootstrap
cat > terraform/bootstrap/terraform.tfvars << EOF
environment = "$MODE"
billing_account_id = "$GCP_BILLING_ACCOUNT_ID"
project_ids = {
  $MODE = "$PROJECT_NAME"
}
region = "$REGION"
service_name = "$SERVICE_NAME"
repo_name = "$REPO_NAME"
EOF
echo "✅ Bootstrap Terraform variables created"

# Create terraform.tfvars file for CICD
mkdir -p terraform/cicd
cat > terraform/cicd/terraform.tfvars << EOF
environment = "$MODE"
project_id = "$PROJECT_NAME"
github_owner = "$REPO_OWNER"
github_repo = "$REPO_NAME"
user_email = "$USER_EMAIL"
region = "$REGION"
service_name = "$SERVICE_NAME"
repo_name = "$REPO_NAME"
EOF
echo "✅ CICD Terraform variables created"

#==========================================================================
# SECTION 5: TERRAFORM DEPLOYMENT (OPTIONAL)
#==========================================================================

# Check if we should skip Terraform deployment
if [ "${SKIP_TERRAFORM:-true}" == "true" ]; then
  echo
  echo "Skipping Terraform deployment (SKIP_TERRAFORM=true)"
  echo "To run Terraform deployment, set SKIP_TERRAFORM=false in .env"
  echo "or run: SKIP_TERRAFORM=false ./scripts/setup/bootstrap.sh"
else
  echo
  echo "DEPLOYING INFRASTRUCTURE"
  echo "------------------------"

  # Initialize and apply Terraform for bootstrap
  echo "Running Terraform bootstrap..."
  cd terraform/bootstrap
  terraform init
  terraform apply -auto-approve
  cd ../..
  echo "✅ Bootstrap Terraform completed"

  # Initialize and apply Terraform for CICD
  echo "Running Terraform CICD setup..."
  cd terraform/cicd
  terraform init
  terraform apply -auto-approve
  cd ../..
  echo "✅ CICD Terraform completed"
fi

echo
echo "===================================================================="
echo "Project $PROJECT_NAME ($MODE environment) setup complete!"
echo "You can now deploy your application with: ./scripts/cicd/deploy.sh"
echo "====================================================================" 