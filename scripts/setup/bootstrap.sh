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

# Check if project exists
if gcloud projects describe "$PROJECT_NAME" &> /dev/null; then
  # For existing projects, we'll set a flag to skip unnecessary Terraform operations
  EXISTING_PROJECT="true"
else
  EXISTING_PROJECT="false"
fi

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
skip_billing_setup = $EXISTING_PROJECT
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
skip_resource_creation = $EXISTING_PROJECT
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
  
  # Before Terraform, create proper service accounts for the project
  echo
  echo "SETTING UP SERVICE ACCOUNTS"
  echo "----------------------------"

  # Create proper service account for the project
  echo "Creating service account for $PROJECT_NAME..."
  SA_NAME="cloudrun-${MODE}-sa"
  SA_EMAIL="${SA_NAME}@${PROJECT_NAME}.iam.gserviceaccount.com"
  EXISTING_SA=$(gcloud iam service-accounts describe $SA_EMAIL --project=$PROJECT_NAME 2>/dev/null || echo "")

  if [[ -z "$EXISTING_SA" ]]; then
    echo "Creating service account $SA_NAME..."
    gcloud iam service-accounts create $SA_NAME --project=$PROJECT_NAME --display-name="Cloud Run Service Account for $MODE" || {
      echo "⚠️ Could not create service account $SA_NAME. You may need to create it manually."
      echo "Command to create manually: gcloud iam service-accounts create $SA_NAME --project=$PROJECT_NAME"
    }
  else
    echo "✅ Service account $SA_EMAIL already exists"
  fi

  # Check for existing Artifact Registry repository
  REPO_EXISTS=$(gcloud artifacts repositories describe "$REPO_NAME" --project="$PROJECT_NAME" --location="$REGION" 2>/dev/null || echo "")

  if [[ -n "$REPO_EXISTS" ]]; then
    echo "✅ Artifact Registry repository $REPO_NAME already exists"
    # Add a note to the Terraform variables file to avoid recreation
    echo "# Repository already exists - creation will be skipped" >> terraform/bootstrap/terraform.tfvars
  else
    echo "Creating Artifact Registry repository $REPO_NAME..."
    # Let Terraform create the repository
    echo "# Repository doesn't exist - will be created by Terraform" >> terraform/bootstrap/terraform.tfvars
  fi

  # Run the Firestore setup script
  echo "Running Firestore setup script..."
  ./scripts/setup/firestore_setup.sh

  # Initialize and apply Terraform for bootstrap
  echo "Running Terraform bootstrap..."
  cd terraform/bootstrap
  terraform init

  # If this is an existing project, only apply if explicitly requested
  if [[ "$EXISTING_PROJECT" == "true" ]]; then
    echo "Project already exists, skipping bootstrap Terraform apply."
    echo "To force apply, run: cd terraform/bootstrap && terraform apply"
  else
    # Run apply with auto-approve for new projects
    terraform apply -auto-approve || {
      echo "⚠️ Terraform apply had errors, but we'll continue if non-critical."
      # Check if we can still deploy the application
      if [[ -z "$(gcloud artifacts repositories list --project=$PROJECT_NAME --location=$REGION --filter="name:$REPO_NAME" --format="value(name)" 2>/dev/null)" ]]; then
        echo "❌ Error: Critical infrastructure is missing, cannot continue."
        echo "Please check the Terraform errors and try again."
        exit 1
      else
        echo "✅ Critical infrastructure exists, continuing with deployment."
      fi
    }
  fi

  cd ../..
  echo "✅ Bootstrap Terraform completed"

  # Firebase Setup Guidance
  echo 
  echo "FIREBASE SETUP"
  echo "-------------"
  echo "For Firebase integration, you need to set up Firebase in the Google Cloud Console:"
  echo "Steps:"
  echo "1. Go to: https://console.firebase.google.com/project/$PROJECT_NAME/overview"
  echo "2. Complete the Firebase setup if not already done"
  echo "3. Create a service account key for Firebase Admin SDK if needed"
  echo "4. Place the key file in service_accounts/firebase-${MODE}.json"

  # Check if Firebase service account key exists
  if [[ ! -f "service_accounts/firebase-${MODE}.json" ]]; then
    echo
    echo "⚠️ Firebase service account key not found. You need to create one."
    echo "Would you like to open Firebase Console now? (y/n)"
    read -r OPEN_FIREBASE
    if [[ "$OPEN_FIREBASE" == "y" || "$OPEN_FIREBASE" == "Y" ]]; then
      # Try to open URL using appropriate command based on OS
      if [[ "$OSTYPE" == "darwin"* ]]; then
        open "https://console.firebase.google.com/project/$PROJECT_NAME/settings/serviceaccounts/adminsdk"
      elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        xdg-open "https://console.firebase.google.com/project/$PROJECT_NAME/settings/serviceaccounts/adminsdk" &>/dev/null
      else
        echo "Please manually visit: https://console.firebase.google.com/project/$PROJECT_NAME/settings/serviceaccounts/adminsdk"
      fi
      
      echo "Once you've downloaded the key file, please rename it to firebase-${MODE}.json"
      echo "and place it in the service_accounts directory."
      echo
      echo "Have you completed this step? (y/n)"
      read -r FIREBASE_KEY_DONE
      if [[ "$FIREBASE_KEY_DONE" != "y" && "$FIREBASE_KEY_DONE" != "Y" ]]; then
        echo "⚠️ You'll need to create the Firebase service account key before the application will work properly."
      fi
    fi
  else
    echo "✅ Firebase service account key found at service_accounts/firebase-${MODE}.json"
  fi

  # CICD Setup including GitHub connection guidance
  echo 
  echo "GITHUB CONNECTION FOR CI/CD"
  echo "--------------------------"

  # First check if GitHub is connected
  GITHUB_CONNECTED=false
  GITHUB_ALREADY_CONNECTED=${GITHUB_ALREADY_CONNECTED:-false}
  
  # Multiple ways to check if GitHub is connected
  if [[ "$GITHUB_ALREADY_CONNECTED" == "true" ]]; then
    echo "✅ GitHub connection confirmed as already authorized via GITHUB_ALREADY_CONNECTED flag"
    GITHUB_CONNECTED=true
  else
    # Try multiple methods to detect GitHub connection
    GITHUB_CONNECTED_REPOS=$(gcloud beta builds repositories list --project="$PROJECT_NAME" --format="value(name)" 2>/dev/null | grep -i "github" || echo "")
    GITHUB_CONNECTED_TRIGGERS=$(gcloud beta builds triggers list --project="$PROJECT_NAME" --format="value(github)" 2>/dev/null || echo "")
    
    if [[ -n "$GITHUB_CONNECTED_REPOS" || -n "$GITHUB_CONNECTED_TRIGGERS" ]]; then
      echo "✅ GitHub connection detected in your GCP project"
      GITHUB_CONNECTED=true
      
      # Recommend setting the flag for future runs
      echo "Add GITHUB_ALREADY_CONNECTED=true to your .env file to skip detection in the future"
    else
      echo "⚠️ GitHub connection not detected. You need to connect GitHub to Cloud Build."
      echo "Steps:"
      echo "1. Go to: https://console.cloud.google.com/cloud-build/triggers/connect?project=$PROJECT_NAME"
      echo "2. Select your GitHub repository: $GITHUB_OWNER/$REPO_NAME"
      echo "3. Install the Cloud Build GitHub app if needed"
      echo
      echo "Would you like to open the GitHub connection page now? (y/n)"
      read -r OPEN_GITHUB
      if [[ "$OPEN_GITHUB" == "y" || "$OPEN_GITHUB" == "Y" ]]; then
        # Try to open URL using appropriate command based on OS
        if [[ "$OSTYPE" == "darwin"* ]]; then
          open "https://console.cloud.google.com/cloud-build/triggers/connect?project=$PROJECT_NAME"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
          xdg-open "https://console.cloud.google.com/cloud-build/triggers/connect?project=$PROJECT_NAME" &>/dev/null
        else
          echo "Please manually visit: https://console.cloud.google.com/cloud-build/triggers/connect?project=$PROJECT_NAME"
        fi
        
        echo ""
        echo "Please confirm when you've completed the GitHub connection setup (y/n):"
        read -r GITHUB_SETUP_DONE
        if [[ "$GITHUB_SETUP_DONE" == "y" || "$GITHUB_SETUP_DONE" == "Y" ]]; then
          GITHUB_CONNECTED=true
          echo "✅ GitHub connection confirmed"
          echo "Add GITHUB_ALREADY_CONNECTED=true to your .env file to skip this step next time"
        fi
      fi
    fi
  fi

  # If GitHub is connected, proceed with deployment setup
  if [[ "$GITHUB_CONNECTED" == "true" ]]; then
    # Mark GitHub as connected in Terraform configuration
    sed -i'.bak' 's/skip_resource_creation = .*/skip_resource_creation = false/' terraform/cicd/terraform.tfvars
    rm -f terraform/cicd/terraform.tfvars.bak 2>/dev/null || true
    
    # Initialize and apply Terraform for CICD
    echo "Running Terraform CICD setup for creating triggers..."
    cd terraform/cicd
    terraform init
    
    # Apply the CICD Terraform configuration
    terraform apply -auto-approve || {
      echo "⚠️ There were some errors in the CICD setup, but we'll continue."
      echo "These are typically not critical and deployment can still proceed."
    }
    cd ../..
    echo "✅ CICD Terraform setup completed"
    
    # Run initial deployment
    echo
    echo "DEPLOYING APPLICATION"
    echo "---------------------"
    echo "Initiating first deployment now..."
    
    # Run deploy script if it exists
    if [[ -f "./scripts/cicd/deploy.sh" ]]; then
      ./scripts/cicd/deploy.sh
    else
      echo "⚠️ Deployment script not found at ./scripts/cicd/deploy.sh"
      echo "Please check your project structure or deploy manually."
    fi
  else
    echo "⚠️ GitHub connection is required for deployment."
    echo "Please connect GitHub to Cloud Build and then run this script again or deploy manually."
  fi
fi

echo
echo "===================================================================="
echo "Project $PROJECT_NAME ($MODE environment) setup complete!"
echo "You can now deploy your application with: ./scripts/cicd/deploy.sh"
echo "====================================================================" 