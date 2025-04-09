#!/bin/bash
# Simplified bootstrap script - skips problematic checks

echo "======================================================================"
echo "            GCP Project Bootstrap Tool (Simplified)                   "
echo "======================================================================"

# Read environment variables
echo "Loading environment variables..."
source .env
GCP_BILLING_ACCOUNT_ID=${GCP_BILLING_ACCOUNT_ID:-}
DEV_SCHEMA_NAME=${DEV_SCHEMA_NAME:-}
MODE=${MODE:-dev}
SKIP_TERRAFORM=true # Always skip Terraform in simplified version

# Load config values using a more portable approach for macOS
echo "Loading project configuration..."
config_file="config"
if [ ! -f "$config_file" ]; then
    echo "Error: Config file not found at $config_file"
    exit 1
fi

# Read all config values from the config file
GCP_PROJECT_ID=$(grep -E "^gcp_project_id" $config_file | cut -d '=' -f 2 | tr -d "[:space:]'" | tr -d '"')
SERVICE_NAME=$(grep -E "^service_name" $config_file | cut -d '=' -f 2 | tr -d "[:space:]'" | tr -d '"')
REPO_NAME=$(grep -E "^repo_name" $config_file | cut -d '=' -f 2 | tr -d "[:space:]'" | tr -d '"')
REGION=$(grep -E "^region" $config_file | cut -d '=' -f 2 | tr -d "[:space:]'" | tr -d '"')

# Determine the project name based on the environment
if [ "$MODE" == "dev" ]; then
    if [ -z "$DEV_SCHEMA_NAME" ]; then
        echo "Error: DEV_SCHEMA_NAME is not set in .env"
        echo "This is required for development environments to create unique projects."
        exit 1
    fi
    PROJECT_NAME="${GCP_PROJECT_ID}-${MODE}-${DEV_SCHEMA_NAME}"
    PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')
elif [ "$MODE" == "staging" ]; then
    PROJECT_NAME="${GCP_PROJECT_ID}-${MODE}"
    PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')
elif [ "$MODE" == "prod" ]; then
    PROJECT_NAME="${GCP_PROJECT_ID}-${MODE}"
    PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')
else
    echo "Error: Invalid MODE value. Must be 'dev', 'staging', or 'prod'."
    exit 1
fi

# Limit project name to 30 characters
if [ ${#PROJECT_NAME} -gt 30 ]; then
    PROJECT_NAME="${PROJECT_NAME:0:30}"
    echo "⚠️ Project name truncated to 30 characters: $PROJECT_NAME"
fi

echo ""
echo "PROJECT SETUP"
echo "-------------"
echo "Bootstrapping project: $PROJECT_NAME (Environment: $MODE)"

# Check project existence
echo "Checking if project $PROJECT_NAME exists..."
if gcloud projects describe "$PROJECT_NAME" &> /dev/null; then
    echo "✅ Project $PROJECT_NAME already exists."
else
    echo "❌ Project $PROJECT_NAME doesn't exist. Please create it manually."
    exit 1
fi

# Grant required permissions to the current user
CURRENT_USER=$(gcloud config get account | tr -d '[:space:]')
echo "Granting Artifact Registry Writer role to $CURRENT_USER..."
gcloud projects add-iam-policy-binding "$PROJECT_NAME" \
    --member="user:$CURRENT_USER" \
    --role="roles/artifactregistry.writer" || echo "❗ Could not add IAM binding, but continuing..."

# Generate Terraform variables
echo ""
echo "TERRAFORM CONFIGURATION"
echo "-----------------------"
echo "Setting up Terraform configuration..."
echo "Note: terraform.tfvars files are gitignored and will be regenerated on each bootstrap run"

# Create bootstrap terraform.tfvars
mkdir -p terraform/bootstrap
cat > terraform/bootstrap/terraform.tfvars << EOF
project_id = "${PROJECT_NAME}"
billing_account = "${GCP_BILLING_ACCOUNT_ID}"
region = "${REGION}"
service_name = "${SERVICE_NAME}"
repo_name = "${REPO_NAME}"
EOF
echo "✅ Bootstrap Terraform variables created"

# Create CICD terraform.tfvars
mkdir -p terraform/cicd
cat > terraform/cicd/terraform.tfvars << EOF
project_id = "${PROJECT_NAME}"
service_name = "${SERVICE_NAME}"
repo_name = "${REPO_NAME}"
environment = "${MODE}"
skip_resource_creation = true
EOF
echo "✅ CICD Terraform variables created"

echo ""
echo "======================================================================"
echo "Project $PROJECT_NAME ($MODE environment) setup complete!"
echo "You can now deploy your application with: ./scripts/cicd/deploy.sh"
echo "======================================================================" 