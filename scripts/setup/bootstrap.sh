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

# Always use the PROJECT_ID from config
PROJECT_ID="$GCP_PROJECT_ID"

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
  # Convert to lowercase using tr (macOS compatible)
  PROJECT_ID_LOWER=$(echo "$PROJECT_ID" | tr '[:upper:]' '[:lower:]')
  DEV_SCHEMA_LOWER=$(echo "$DEV_SCHEMA_NAME" | tr '[:upper:]' '[:lower:]')
  PROJECT_NAME="${PROJECT_ID_LOWER}-dev-${DEV_SCHEMA_LOWER}"
elif [ "$MODE" == "staging" ]; then
  PROJECT_ID_LOWER=$(echo "$PROJECT_ID" | tr '[:upper:]' '[:lower:]')
  PROJECT_NAME="${PROJECT_ID_LOWER}-staging"
elif [ "$MODE" == "prod" ]; then
  PROJECT_ID_LOWER=$(echo "$PROJECT_ID" | tr '[:upper:]' '[:lower:]')
  PROJECT_NAME="${PROJECT_ID_LOWER}-prod"
else
  echo "❌ Error: Invalid MODE: $MODE. Must be dev, staging, or prod."
  exit 1
fi

echo "Bootstrapping project: $PROJECT_NAME (Environment: $MODE)"

# Check active gcloud configuration
ACTIVE_PROJECT=$(gcloud config get-value project 2>/dev/null)
if [ "$ACTIVE_PROJECT" != "$PROJECT_NAME" ]; then
  echo "⚠️ WARNING: Your active gcloud configuration is using project: $ACTIVE_PROJECT"
  echo "  But this script will deploy to: $PROJECT_NAME"
  read -p "  Do you want to switch your gcloud config to $PROJECT_NAME? (y/n) " SWITCH_PROJECT
  
  if [[ $SWITCH_PROJECT == "y" || $SWITCH_PROJECT == "Y" ]]; then
    echo "Switching gcloud configuration to $PROJECT_NAME..."
    gcloud config set project $PROJECT_NAME
    echo "✅ Active project switched to $PROJECT_NAME"
  else
    echo "Continuing with current configuration. Commands will target $PROJECT_NAME explicitly."
    echo "Note that any manual gcloud commands you run will still target $ACTIVE_PROJECT unless you specify --project=$PROJECT_NAME"
  fi
else
  echo "✅ Active gcloud configuration matches target project: $PROJECT_NAME"
fi

echo "Checking if project $PROJECT_NAME exists..."

# Check if project exists
if gcloud projects describe "$PROJECT_NAME" &> /dev/null; then
  echo "✅ Project $PROJECT_NAME already exists."
  
  # Check permissions
  echo "Checking permissions..."
  if gcloud projects get-iam-policy "$PROJECT_NAME" &> /dev/null; then
    echo "✅ You have sufficient IAM permissions on this project."
    
    # Get the current user
    CURRENT_USER=$(gcloud config get-value account)
    
    if [ -z "$CURRENT_USER" ]; then
      echo "❌ Error: Could not determine current user. Please run 'gcloud auth login' first."
      exit 1
    fi
      
    # Check if custom developer role exists already
    ROLE_EXISTS=$(gcloud iam roles list --project=$PROJECT_NAME --filter="name:projects/$PROJECT_NAME/roles/developer" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -z "$ROLE_EXISTS" ]; then
      echo "Creating custom developer role..."
      # Create temporary file for role definition
      cat > /tmp/developer-role.yaml << EOF
title: Developer
description: Custom role for application developers
stage: GA
includedPermissions:
- artifactregistry.repositories.create
- artifactregistry.repositories.get
- artifactregistry.repositories.list
- artifactregistry.repositories.uploadArtifacts
- artifactregistry.tags.create
- artifactregistry.tags.get
- artifactregistry.tags.list
- artifactregistry.tags.update
- run.services.create
- run.services.get
- run.services.list
- run.services.update
- storage.objects.create
- storage.objects.delete
- storage.objects.get
- storage.objects.list
- storage.objects.update
EOF
      
      # Create custom role
      gcloud iam roles create developer --project=$PROJECT_NAME --file=/tmp/developer-role.yaml
      rm /tmp/developer-role.yaml
      echo "✅ Custom developer role created."
    else
      echo "✅ Custom developer role already exists."
    fi
    
    # Check if user has the developer role
    HAS_ROLE=$(gcloud projects get-iam-policy $PROJECT_NAME --format=json | \
      jq -r ".bindings[] | select(.role == \"projects/$PROJECT_NAME/roles/developer\") | .members[] | select(. == \"user:$CURRENT_USER\")" 2>/dev/null || echo "")
    
    if [ -z "$HAS_ROLE" ]; then
      echo "Granting developer role to $CURRENT_USER..."
      gcloud projects add-iam-policy-binding $PROJECT_NAME \
        --member="user:$CURRENT_USER" \
        --role="projects/$PROJECT_NAME/roles/developer"
      echo "✅ Developer role assigned."
    else
      echo "✅ User already has developer role."
    fi
    
    # Check Artifact Registry permissions specifically
    echo "Checking Artifact Registry access..."
    if gcloud artifacts repositories list --project="$PROJECT_NAME" --location="$REGION" &> /dev/null; then
      echo "✅ You have Artifact Registry permissions."
    else
      echo "⚠️ You need additional Artifact Registry permissions. Adding them now..."
      
      # Grant Artifact Registry permissions directly in case the custom role isn't sufficient
      echo "Granting Artifact Registry Writer role to $CURRENT_USER..."
      gcloud projects add-iam-policy-binding "$PROJECT_NAME" \
        --member="user:$CURRENT_USER" \
        --role="roles/artifactregistry.writer"
      
      echo "✅ Required permissions added."
    fi
  else
    echo "❌ Error: You don't have sufficient permissions on this project."
    exit 1
  fi
else
  echo "Project doesn't exist. A new project needs to be created."
  
  # Now check for billing account only if we need to create a new project
  if [ -z "$GCP_BILLING_ACCOUNT_ID" ]; then
    echo "❌ Error: GCP_BILLING_ACCOUNT_ID is not set in .env"
    echo "  This is required to create a new project."
    echo "  If you're joining an existing project, make sure the project ID is correct."
    exit 1
  fi
  
  echo "Checking billing account..."
  
  # Check if billing account exists and we have access to it
  if gcloud billing accounts list --filter="ACCOUNT_ID:$GCP_BILLING_ACCOUNT_ID" --format="value(ACCOUNT_ID)" | grep -q "$GCP_BILLING_ACCOUNT_ID"; then
    echo "✅ Billing account exists. Creating project $PROJECT_NAME..."
    gcloud projects create "$PROJECT_NAME" --name="$PROJECT_NAME"
    
    echo "Linking billing account to project..."
    gcloud billing projects link "$PROJECT_NAME" --billing-account="$GCP_BILLING_ACCOUNT_ID"
    
    # Get the current user
    CURRENT_USER=$(gcloud config get-value account)
    
    # First grant basic editor permissions needed for next steps
    echo "Granting basic editor permissions to $CURRENT_USER..."
    gcloud projects add-iam-policy-binding "$PROJECT_NAME" \
      --member="user:$CURRENT_USER" \
      --role="roles/editor"
    
    # Create custom developer role
    echo "Creating custom developer role..."
    # Create temporary file for role definition
    cat > /tmp/developer-role.yaml << EOF
title: Developer
description: Custom role for application developers
stage: GA
includedPermissions:
- artifactregistry.repositories.create
- artifactregistry.repositories.get
- artifactregistry.repositories.list
- artifactregistry.repositories.uploadArtifacts
- artifactregistry.tags.create
- artifactregistry.tags.get
- artifactregistry.tags.list
- artifactregistry.tags.update
- run.services.create
- run.services.get
- run.services.list
- run.services.update
- storage.objects.create
- storage.objects.delete
- storage.objects.get
- storage.objects.list
- storage.objects.update
EOF

    # Create custom role
    gcloud iam roles create developer --project=$PROJECT_NAME --file=/tmp/developer-role.yaml
    rm /tmp/developer-role.yaml
    
    # Assign developer role to current user
    echo "Granting developer role to $CURRENT_USER..."
    gcloud projects add-iam-policy-binding $PROJECT_NAME \
      --member="user:$CURRENT_USER" \
      --role="projects/$PROJECT_NAME/roles/developer"
    
    echo "✅ Custom developer role created and assigned."
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
echo "Setting up Terraform configuration..."

# Instead of using git commands, use the config values
GITHUB_OWNER=$(extract_config_value "github_owner")
REPO_NAME=$(extract_config_value "repo_name")
USER_EMAIL=$(git config --get user.email)

# Prepare Terraform variables
echo "Setting up Terraform configuration..."
echo "Note: terraform.tfvars files are gitignored and will be regenerated on each bootstrap run"

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
github_owner = "$GITHUB_OWNER"
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