#!/bin/bash
set -e

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to handle Firebase setup for a project - complete rewrite for better handling
setup_firebase() {
  local project_id=$1
  
  echo -e "${BLUE}Setting up Firebase for project $project_id...${NC}"
  
  # First, ensure Firebase API is enabled - this is a prerequisite
  echo -e "${BLUE}Enabling Firebase API...${NC}"
  gcloud services enable firebase.googleapis.com --project="$project_id" >/dev/null 2>&1 || 
    echo -e "${YELLOW}Firebase API already enabled or unable to enable - continuing...${NC}"
  
  # Wait for API enablement to propagate
  sleep 3
  
  # Multi-faceted verification of Firebase status
  echo -e "${BLUE}Verifying Firebase status using multiple methods...${NC}"
  
  # Method 1: Check Firebase project list via Firebase CLI
  echo -e "${BLUE}Checking Firebase project list...${NC}"
  firebase_listing=$(firebase projects:list --json 2>/dev/null)
  firebase_cli_result=$?
  
  if [ $firebase_cli_result -eq 0 ] && [[ "$firebase_listing" == *"\"projectId\":\"$project_id\""* ]]; then
    echo -e "${GREEN}Project found in Firebase CLI project list${NC}"
    firebase_registered=true
  else
    echo -e "${YELLOW}Project not found in Firebase CLI project list${NC}"
    firebase_registered=false
  fi
  
  # Method 2: Check for Firestore database existence
  echo -e "${BLUE}Checking for Firestore database...${NC}"
  firestore_check=$(gcloud firestore databases list --project="$project_id" 2>/dev/null)
  
  if [[ "$firestore_check" == *"(default)"* ]]; then
    echo -e "${GREEN}Firestore database exists - project is likely registered with Firebase${NC}"
    firestore_exists=true
  else
    echo -e "${YELLOW}Firestore database not found${NC}"
    firestore_exists=false
  fi
  
  # Method 3: Check Firebase Management API
  echo -e "${BLUE}Checking Firebase Management API...${NC}"
  firebase_api_check=$(curl -s -X GET \
    "https://firebase.googleapis.com/v1beta1/projects/$project_id" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" 2>/dev/null)
  
  if [[ "$firebase_api_check" == *"\"projectId\": \"$project_id\""* ]] || [[ "$firebase_api_check" == *"\"name\": \"projects/$project_id\""* ]]; then
    echo -e "${GREEN}Project found via Firebase Management API${NC}"
    firebase_api_registered=true
  else
    echo -e "${YELLOW}Project not found via Firebase Management API or access denied${NC}"
    firebase_api_registered=false
  fi
  
  # Combined decision based on all methods
  if [ "$firebase_registered" = true ] || [ "$firestore_exists" = true ] || [ "$firebase_api_registered" = true ]; then
    echo -e "${GREEN}Project $project_id is registered with Firebase${NC}"
    project_registered=true
  else
    echo -e "${YELLOW}Project $project_id needs to be registered with Firebase - attempting registration...${NC}"
    project_registered=false
    
    # Ensure the current user has Firebase Admin role before attempting registration
    echo -e "${BLUE}Ensuring current user has Firebase Admin role...${NC}"
    USER_EMAIL=$(gcloud config get-value account 2>/dev/null)
    
    # Check if user already has the role
    gcloud projects get-iam-policy "$project_id" --format="json" | grep -q "\"role\": \"roles/firebase.admin\".*$USER_EMAIL"
    if [ $? -ne 0 ]; then
      echo -e "${YELLOW}Adding Firebase Admin role to current user...${NC}"
      gcloud projects add-iam-policy-binding "$project_id" \
        --member="user:$USER_EMAIL" \
        --role="roles/firebase.admin" --quiet >/dev/null 2>&1
      
      if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to add Firebase Admin role - insufficient permissions${NC}"
        echo -e "${YELLOW}To continue, ask a project owner to run:${NC}"
        echo "gcloud projects add-iam-policy-binding $project_id --member=\"user:$USER_EMAIL\" --role=\"roles/firebase.admin\""
      else
        echo -e "${GREEN}Firebase Admin role added successfully${NC}"
        # Wait for IAM changes to propagate
        sleep 8
      fi
    else
      echo -e "${GREEN}User already has Firebase Admin role${NC}"
    fi
    
    # Try multiple methods to register the project with Firebase
    
    # Method 1: Firebase CLI
    echo -e "${BLUE}Attempting to register project via Firebase CLI...${NC}"
    firebase projects:addfirebase "$project_id" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}Successfully registered project with Firebase via CLI${NC}"
      project_registered=true
    else
      echo -e "${YELLOW}Firebase CLI registration failed - trying alternative method...${NC}"
      
      # Method 2: Direct gcloud command if available
      echo -e "${BLUE}Attempting registration via gcloud...${NC}"
      # Some environments might have this command
      gcloud alpha firebase projects add "$project_id" >/dev/null 2>&1 || gcloud firebase projects:addfirebase "$project_id" >/dev/null 2>&1
      
      if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully registered project with Firebase via gcloud${NC}"
        project_registered=true
      else
        echo -e "${YELLOW}Automatic Firebase registration failed${NC}"
        
        # Guidance for manual addition
        echo -e "${YELLOW}Please manually add the project to Firebase by visiting:${NC}"
        echo -e "${BLUE}https://console.firebase.google.com/?pli=1${NC}"
        echo -e "${YELLOW}1. Click 'Add project'${NC}"
        echo -e "${YELLOW}2. Select '$project_id' from the project dropdown${NC}"
        echo -e "${YELLOW}3. Follow the prompts to complete the setup${NC}"
        
        # Ask for confirmation unless skip is enabled
        if [ "$SKIP_CONFIRM" != "true" ]; then
          read -p "Have you completed the Firebase setup (y/n)? " -n 1 -r
          echo ""
          if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Continuing with setup based on your confirmation${NC}"
            project_registered=true
          else
            echo -e "${YELLOW}Continuing without confirmed Firebase registration${NC}"
          fi
        fi
      fi
    fi
  fi
  
  # Always try to set up Firestore, regardless of Firebase registration status
  echo -e "${BLUE}Setting up Firestore database...${NC}"
  gcloud services enable firestore.googleapis.com --project="$project_id" >/dev/null 2>&1
  
  # Check if Firestore database exists
  firestore_check=$(gcloud firestore databases list --project="$project_id" 2>/dev/null | grep -c "(default)" || echo "0")
  
  if [ "$firestore_check" = "0" ]; then
    echo -e "${BLUE}Creating Firestore database...${NC}"
    gcloud firestore databases create --location=nam5 --project="$project_id" >/dev/null 2>&1
    
    if [ $? -ne 0 ]; then
      echo -e "${YELLOW}Could not automatically create Firestore database${NC}"
      echo -e "${YELLOW}Please manually create a Firestore database:${NC}"
      echo -e "${BLUE}1. Visit: https://console.firebase.google.com/project/$project_id/firestore${NC}"
      echo -e "${BLUE}2. Follow the prompts to create a database in Native mode${NC}"
      echo -e "${BLUE}3. Choose 'nam5' (North America) for the location${NC}"
      
      if [ "$SKIP_CONFIRM" != "true" ]; then
        read -p "Press Enter after creating the database, or type 'skip' to continue anyway: " response
        if [ "$response" != "skip" ]; then
          echo -e "${GREEN}Continuing with setup based on your confirmation${NC}"
        else
          echo -e "${YELLOW}Continuing without confirmed Firestore database creation${NC}"
        fi
      fi
    else
      echo -e "${GREEN}Firestore database created successfully${NC}"
    fi
  else
    echo -e "${GREEN}Firestore database already exists${NC}"
  fi
  
  # Handle Firebase Admin service account and key
  SA_NAME="firebase-admin"
  SA_EMAIL="$SA_NAME@$project_id.iam.gserviceaccount.com"
  
  echo -e "${BLUE}Managing Firebase Admin service account...${NC}"
  sa_exists=$(gcloud iam service-accounts list --project="$project_id" --filter="email:$SA_EMAIL" --format="value(email)" 2>/dev/null || echo "")
  
  if [ -z "$sa_exists" ]; then
    echo -e "${BLUE}Creating Firebase Admin service account...${NC}"
    gcloud iam service-accounts create "$SA_NAME" \
      --project="$project_id" \
      --display-name="Firebase Admin Service Account" \
      --description="Service account for Firebase Admin SDK" >/dev/null 2>&1
    
    if [ $? -ne 0 ]; then
      echo -e "${YELLOW}Warning: Failed to create service account - it may already exist with a different name${NC}"
      
      # Try to list existing service accounts that might be used for Firebase
      echo -e "${BLUE}Checking for existing service accounts...${NC}"
      gcloud iam service-accounts list --project="$project_id" --format="table(email,displayName)" | grep -i "firebase\|firestore"
    else
      echo -e "${GREEN}Service account created successfully${NC}"
      # Wait for the service account to be fully created
      sleep 5
    fi
  else
    echo -e "${GREEN}Firebase Admin service account already exists${NC}"
  fi
  
  # Grant necessary roles to the service account if it exists
  if [ -n "$sa_exists" ] || [ $? -eq 0 ]; then
    echo -e "${BLUE}Granting necessary roles to Firebase Admin service account...${NC}"
    
    # Array of required roles
    ROLES=(
      "roles/firebase.admin"
      "roles/firestore.admin"
      "roles/datastore.user"
      "roles/secretmanager.secretAccessor"
    )
    
    for role in "${ROLES[@]}"; do
      echo -e "${BLUE}Granting $role...${NC}"
      gcloud projects add-iam-policy-binding "$project_id" \
        --member="serviceAccount:$SA_EMAIL" \
        --role="$role" --quiet >/dev/null 2>&1
        
      if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Warning: Failed to grant $role - this may affect functionality${NC}"
      fi
    done
  fi
  
  # Set up key for Firebase Admin service account
  mkdir -p secrets
  SA_KEY_FILE="secrets/firebase-admin-key-$project_id.json"
  
  if [ ! -f "$SA_KEY_FILE" ]; then
    echo -e "${BLUE}Creating key for Firebase Admin service account...${NC}"
    gcloud iam service-accounts keys create "$SA_KEY_FILE" \
      --project="$project_id" \
      --iam-account="$SA_EMAIL" >/dev/null 2>&1
      
    if [ $? -ne 0 ]; then
      echo -e "${YELLOW}Warning: Failed to create service account key${NC}"
      echo -e "${YELLOW}Command to create key manually: ${NC}"
      echo "gcloud iam service-accounts keys create \"$SA_KEY_FILE\" --project=\"$project_id\" --iam-account=\"$SA_EMAIL\""
    else
      echo -e "${GREEN}Service account key created at $SA_KEY_FILE${NC}"
      # Set appropriate file permissions
      chmod 600 "$SA_KEY_FILE"
    fi
  else
    echo -e "${GREEN}Firebase Admin key already exists at $SA_KEY_FILE${NC}"
  fi
  
  # Store the key in Secret Manager if it was created
  if [ -f "$SA_KEY_FILE" ]; then
    echo -e "${BLUE}Storing Firebase Admin key in Secret Manager...${NC}"
    
    # Enable Secret Manager API
    gcloud services enable secretmanager.googleapis.com --project="$project_id" >/dev/null 2>&1
    
    # Check if the secret already exists
    SECRET_EXISTS=$(gcloud secrets list --project="$project_id" --filter="name:firebase-credentials" --format="value(name)" 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$SECRET_EXISTS" = "0" ]; then
      echo -e "${BLUE}Creating new Firebase credentials secret...${NC}"
      gcloud secrets create firebase-credentials \
        --data-file="$SA_KEY_FILE" \
        --project="$project_id" >/dev/null 2>&1
        
      if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Warning: Failed to create secret${NC}"
      else
        echo -e "${GREEN}Secret created successfully${NC}"
      fi
    else
      echo -e "${BLUE}Updating existing Firebase credentials secret...${NC}"
      gcloud secrets versions add firebase-credentials \
        --data-file="$SA_KEY_FILE" \
        --project="$project_id" >/dev/null 2>&1
        
      if [ $? -ne 0 ]; then
        echo -e "${YELLOW}Warning: Failed to update secret${NC}"
      else
        echo -e "${GREEN}Secret updated successfully${NC}"
      fi
    fi
  fi
  
  echo -e "${GREEN}Firebase setup completed for $project_id${NC}"
  echo -e "${BLUE}You can access your Firebase project at: ${NC}https://console.firebase.google.com/project/$project_id/overview"
  return 0
}

# Default values
ENVIRONMENTS=()
DEVELOPER_NAME=$(whoami)
FORCE_NEW=false
SKIP_CONFIRM=false
BILLING_ACCOUNT_ID=""

# Load .env file if it exists
if [ -f ".env" ]; then
  source .env
  if [ -n "$BILLING_ACCOUNT_ID" ]; then
    echo -e "${BLUE}Loaded BILLING_ACCOUNT_ID from .env file${NC}"
  fi
fi

function print_usage() {
  echo "Usage: $0 [--all|--prod|--staging|--dev] [--billing-account BILLING_ACCOUNT_ID] [options]"
  echo "  Environment options (required, choose at least one):"
  echo "    --all                 Bootstrap all environments (dev, staging, prod)"
  echo "    --prod                Bootstrap production environment"
  echo "    --staging             Bootstrap staging environment"
  echo "    --dev                 Bootstrap development environment"
  echo ""
  echo "  Other options:"
  echo "    --billing-account     GCP Billing Account ID (required if not in .env)"
  echo "    --developer           Developer name for dev environment (default: current user)"
  echo "    --force-new           Force creation of new infrastructure even if it exists"
  echo "    --yes                 Skip confirmation prompts"
  echo "    --github-key          Only generate GitHub Actions service account key"
  echo "    --firebase-setup      Only run the Firebase setup portion of the script"
  echo "    --help                Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0 --all                Bootstrap all environments"
  echo "  $0 --dev                Bootstrap only the development environment"
  echo "  $0 --prod --staging     Bootstrap production and staging environments"
  echo "  $0 --github-key         Only generate GitHub Actions service account key"
}

# Parse command line arguments
GITHUB_KEY_ONLY=false
FIREBASE_SETUP_ONLY=false
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --all)
      ENVIRONMENTS=("dev" "staging" "prod")
      shift
      ;;
    --prod)
      ENVIRONMENTS+=("prod")
      shift
      ;;
    --staging)
      ENVIRONMENTS+=("staging")
      shift
      ;;
    --dev)
      ENVIRONMENTS+=("dev")
      shift
      ;;
    --billing-account)
      BILLING_ACCOUNT_ID="$2"
      shift
      shift
      ;;
    --developer)
      DEVELOPER_NAME="$2"
      shift
      shift
      ;;
    --force-new)
      FORCE_NEW=true
      shift
      ;;
    --yes)
      SKIP_CONFIRM=true
      shift
      ;;
    --github-key)
      GITHUB_KEY_ONLY=true
      shift
      ;;
    --firebase-setup)
      FIREBASE_SETUP_ONLY=true
      shift
      ;;
    --help)
      print_usage
      exit 0
      ;;
    *)
      echo -e "${RED}Error: Unknown option $1${NC}"
      print_usage
      exit 1
      ;;
  esac
done

# Load configuration file
if [ ! -f "config.yaml" ]; then
  echo -e "${RED}Error: config.yaml file not found!${NC}"
  exit 1
fi

# Check if .env file exists, if not create from template
if [ ! -f ".env" ]; then
  if [ -f ".env.example" ]; then
    cp .env.example .env
    echo -e "${YELLOW}Created .env file from .env.example template. Please edit it with your settings.${NC}"
    echo -e "${YELLOW}You may need to restart the bootstrap process after updating your .env file.${NC}"
    exit 0
  else
    echo -e "${RED}Error: .env.example template not found!${NC}"
    exit 1
  fi
fi

# Check for billing account ID if not GitHub key only
if [ -z "$BILLING_ACCOUNT_ID" ] && [ "$GITHUB_KEY_ONLY" != "true" ]; then
  echo -e "${RED}Error: Billing account ID is required. Please provide using --billing-account or set in .env file${NC}"
  print_usage
  exit 1
fi

# Check billing permissions
check_billing_permissions() {
  if [ -n "$BILLING_ACCOUNT_ID" ]; then
    echo -e "${BLUE}Checking billing account permissions...${NC}"
    
    # Check if user can get billing account info
    billing_output=$(gcloud billing accounts describe $BILLING_ACCOUNT_ID 2>&1)
    billing_result=$?
    
    if [ $billing_result -ne 0 ]; then
      echo -e "${RED}Error: You do not have permissions to access billing account $BILLING_ACCOUNT_ID${NC}"
      echo -e "${YELLOW}Required permissions:${NC}"
      echo -e "- billing.accounts.get"
      echo -e "- billing.accounts.getIamPolicy"
      echo -e "- billing.projects.create"
      echo -e "${YELLOW}Error details: ${billing_output}${NC}"
      echo -e "${YELLOW}Please contact your Google Cloud administrator to grant you these permissions.${NC}"
      return 1
    else
      echo -e "${GREEN}Billing account permissions check passed${NC}"
    fi
  else
    echo -e "${YELLOW}No billing account ID specified, skipping billing permissions check${NC}"
  fi
}

# Enable common APIs required for the project
enable_common_apis() {
  local project_id=$1
  
  # Core APIs needed for most operations
  CORE_APIS=(
    "serviceusage.googleapis.com"
    "cloudbilling.googleapis.com" 
    "cloudresourcemanager.googleapis.com"
    "iam.googleapis.com"
    "secretmanager.googleapis.com"
    "artifactregistry.googleapis.com"
    "run.googleapis.com"
    "firebase.googleapis.com"
    "firestore.googleapis.com"
    "cloudresourcemanager.googleapis.com"
  )
  
  # First check if user has permissions to enable APIs
  echo -e "${BLUE}Checking service usage permissions...${NC}"
  local service_check=$(gcloud services list --project "$project_id" --filter="config.name=serviceusage.googleapis.com" --format="value(config.name)" 2>&1)
  local service_result=$?
  
  if [ $service_result -ne 0 ]; then
    echo -e "${YELLOW}Warning: Unable to check enabled services. This may indicate missing permissions.${NC}"
    echo -e "${YELLOW}Required permissions: serviceusage.services.list${NC}"
    echo -e "${YELLOW}You may encounter issues with API enablement in later steps.${NC}"
  fi
  
  # Enable core APIs one by one for better error handling
  for api in "${CORE_APIS[@]}"; do
    echo -e "${BLUE}Enabling $api...${NC}"
    local enable_output=$(gcloud services enable $api --project $project_id 2>&1)
    local enable_result=$?
    
    if [ $enable_result -ne 0 ]; then
      if [[ "$enable_output" == *"already enabled"* ]]; then
        echo -e "${GREEN}$api is already enabled${NC}"
      else
        echo -e "${YELLOW}Warning: Failed to enable $api. This might affect subsequent operations.${NC}"
        echo -e "${YELLOW}Error details: $enable_output${NC}"
      fi
    else
      echo -e "${GREEN}Enabled $api${NC}"
    fi
  done
  
  # Wait a moment for API enablement to propagate
  echo -e "${BLUE}Waiting for API enablement to propagate...${NC}"
  sleep 3
}

# Read project name and ID from config.yaml
PROJECT_NAME=$(grep -A1 "name:" config.yaml | head -n2 | tail -n1 | sed 's/.*: //' | sed 's/"//g')
PROJECT_ID=$(grep "id:" config.yaml | head -n1 | sed 's/.*id: //' | sed 's/"//g')
REGION=$(grep -A1 "region:" config.yaml | head -n2 | tail -n1 | sed 's/.*: //' | sed 's/"//g')

# Debug prints
echo "Debug: Extracted values from config.yaml:"
echo "PROJECT_NAME='$PROJECT_NAME'"
echo "PROJECT_ID='$PROJECT_ID'"
echo "REGION='$REGION'"

# Verify we have the project information
if [ -z "$PROJECT_ID" ]; then
  echo -e "${RED}Error: Could not find project.id in config.yaml${NC}"
  exit 1
fi

# If only Firebase setup is requested, do that and exit
if [ "$FIREBASE_SETUP_ONLY" == "true" ]; then
  echo -e "${GREEN}Firebase setup only mode selected${NC}"
  
  # Ensure at least dev environment is specified
  if [ ${#ENVIRONMENTS[@]} -eq 0 ]; then
    ENVIRONMENTS+=("dev")
  fi
  
  for env in "${ENVIRONMENTS[@]}"; do
    echo -e "${BLUE}=== Setting up Firebase for $env environment ===${NC}"
    
    # Determine the project ID based on environment
    if [ "$env" == "dev" ]; then
      actual_project_id="${PROJECT_ID}-${env}-${DEVELOPER_NAME}"
    else
      actual_project_id="${PROJECT_ID}-${env}"
    fi
    
    echo -e "${BLUE}Setting up Firebase for project: $actual_project_id${NC}"
    setup_firebase "$actual_project_id"
    echo ""
  done
  
  echo -e "${GREEN}Firebase setup process complete!${NC}"
  exit 0
fi

# If only generating GitHub Key, do that and exit
if [ "$GITHUB_KEY_ONLY" == "true" ]; then
  echo -e "${GREEN}Generating GitHub Actions key only mode selected${NC}"
  # Create a service account for GitHub Actions if it doesn't exist
  SA_NAME="github-actions"
  DEV_PROJECT_ID="${PROJECT_ID}-dev-${DEVELOPER_NAME}"
  SA_EMAIL="${SA_NAME}@${DEV_PROJECT_ID}.iam.gserviceaccount.com"

  echo -e "${BLUE}Checking if GitHub Actions service account exists...${NC}"
  sa_exists=$(gcloud iam service-accounts list --filter="email=${SA_EMAIL}" --format="value(email)" 2>/dev/null || echo "")

  if [ -z "$sa_exists" ]; then
    echo -e "${GREEN}Creating GitHub Actions service account...${NC}"
    gcloud iam service-accounts create $SA_NAME \
      --display-name="GitHub Actions Service Account" \
      --description="Used for GitHub Actions deployments" || echo -e "${YELLOW}Warning: Failed to create service account. It may already exist or you might not have permissions.${NC}"

    # Wait for the service account to be fully created
    sleep 5
    
    # Grant necessary roles for the service accounts
    echo -e "${BLUE}Granting roles to service account...${NC}"
    for env in "${ENVIRONMENTS[@]}"; do
      actual_project_id="${PROJECT_ID}-${env}"
      
      echo -e "${BLUE}Granting roles to service account for $env environment...${NC}"
      gcloud projects add-iam-policy-binding $actual_project_id \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/run.admin" || echo -e "${YELLOW}Warning: Failed to grant run.admin role. You might not have sufficient permissions.${NC}"
        
      gcloud projects add-iam-policy-binding $actual_project_id \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/storage.admin" || echo -e "${YELLOW}Warning: Failed to grant storage.admin role. You might not have sufficient permissions.${NC}"
        
      gcloud projects add-iam-policy-binding $actual_project_id \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/cloudbuild.builds.builder" || echo -e "${YELLOW}Warning: Failed to grant cloudbuild.builds.builder role. You might not have sufficient permissions.${NC}"
        
      gcloud projects add-iam-policy-binding $actual_project_id \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/iam.serviceAccountUser" || echo -e "${YELLOW}Warning: Failed to grant iam.serviceAccountUser role. You might not have sufficient permissions.${NC}"
    done
  else
    echo -e "${YELLOW}GitHub Actions service account already exists. Skipping creation.${NC}"
  fi

  # Generate key for the service account
  echo -e "${BLUE}Generating key for GitHub Actions service account...${NC}"
  SA_KEY_FILE="secrets/github-actions-key.json"
  gcloud iam service-accounts keys create $SA_KEY_FILE --iam-account=$SA_EMAIL || echo -e "${YELLOW}Warning: Failed to create service account key. You might not have sufficient permissions.${NC}"

  # Continue only if the key was created
  if [ -f "$SA_KEY_FILE" ]; then
    # Define the correct project IDs for each environment
    DEV_PROJECT_ID="${PROJECT_ID}-dev-${DEVELOPER_NAME}"
    STAGING_PROJECT_ID="${PROJECT_ID}-staging"
    PROD_PROJECT_ID="${PROJECT_ID}-prod"
    
    echo -e "${YELLOW}"
    echo "======================================================================================"
    echo "                 ACTION REQUIRED: GitHub Secrets Setup                              "
    echo "======================================================================================"
    echo -e "${NC}"
    echo "To enable CI/CD with GitHub Actions, add the following secrets to your repository:"
    echo ""
    echo "1. GCP_SA_KEY"
    echo "   Value: The content of the $SA_KEY_FILE file that was just created"
    echo "   (This file contains the service account credentials for GitHub Actions)"
    echo ""
    echo "2. DEV_PROJECT_ID"
    echo "   Value: ${DEV_PROJECT_ID}"
    echo ""
    echo "3. STAGING_PROJECT_ID"
    echo "   Value: ${STAGING_PROJECT_ID}"
    echo ""
    echo "4. PROD_PROJECT_ID"
    echo "   Value: ${PROD_PROJECT_ID}"
    echo ""
    echo "After adding these secrets, delete the $SA_KEY_FILE file for security reasons:"
    echo "   rm $SA_KEY_FILE"
    echo ""
    echo -e "${YELLOW}"
    echo "======================================================================================"
    echo -e "${NC}"
  else
    echo -e "${YELLOW}Note: Service account key creation failed. You may need to create this manually.${NC}"
  fi

  echo -e "${GREEN}GitHub key generation process complete!${NC}"
  exit 0
fi

# Check if any environment was selected
if [ ${#ENVIRONMENTS[@]} -eq 0 ]; then
  echo -e "${RED}Error: No environment specified. Please use --all, --prod, --staging, or --dev${NC}"
  print_usage
  exit 1
fi

# Print settings and ask for confirmation
echo -e "${GREEN}Bootstrap Settings:${NC}"
echo -e "${GREEN}  Project Name:${NC} $PROJECT_NAME"
echo -e "${GREEN}  Project ID:${NC} $PROJECT_ID"
echo -e "${GREEN}  Region:${NC} $REGION"
echo -e "${GREEN}  Environments:${NC} ${ENVIRONMENTS[*]}"
echo -e "${GREEN}  Billing Account:${NC} $BILLING_ACCOUNT_ID"

if [[ " ${ENVIRONMENTS[*]} " =~ " dev " ]]; then
  echo -e "${GREEN}  Developer:${NC} $DEVELOPER_NAME"
fi

# Confirm with user unless --yes flag is used
if [ "$SKIP_CONFIRM" != "true" ]; then
  echo ""
  echo -e "${YELLOW}WARNING: This will create or configure Google Cloud projects and begin billing to the account specified.${NC}"
  read -p "Do you want to continue? (y/n) " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation canceled."
    exit 0
  fi
fi

# Bootstrap a single environment
bootstrap_environment() {
  local env=$1
  
  echo -e "${BLUE}Bootstrapping $env environment...${NC}"
  
  if [ "$env" == "dev" ]; then
    project_id="${PROJECT_ID}-${env}-${DEVELOPER_NAME}"
  else
    project_id="${PROJECT_ID}-${env}"
  fi
  
  # Check if project exists
  local project_exists=$(gcloud projects list --filter="PROJECT_ID:$project_id" --format="value(PROJECT_ID)" 2>/dev/null)
  
  if [ -z "$project_exists" ]; then
    echo -e "${YELLOW}Project $project_id does not exist.${NC}"
    
    # Check if the user can create projects
    local can_create=$(gcloud projects list 2>&1)
    if [[ "$can_create" == *"PERMISSION_DENIED"* ]]; then
      echo -e "${RED}Error: You don't have permission to create projects.${NC}"
      echo -e "${YELLOW}Required permissions: resourcemanager.projects.create${NC}"
      echo -e "${YELLOW}Please contact your Google Cloud administrator to grant you this permission.${NC}"
      return 1
    fi
    
    # Check if billing account permissions are sufficient before creating project
    check_billing_permissions
    if [ $? -ne 0 ]; then
      return 1
    fi
    
    echo -e "${YELLOW}This script will create project $project_id and begin billing to account $BILLING_ACCOUNT_ID.${NC}"
    echo -e "${YELLOW}Estimated costs may vary based on usage.${NC}"
    read -p "Do you want to proceed? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo -e "${RED}Operation cancelled by user.${NC}"
      return 1
    fi
    
    # Create the project
    echo -e "${BLUE}Creating project $project_id...${NC}"
    gcloud projects create $project_id --name="$PROJECT_NAME $env" >/dev/null 2>&1
    
    if [ $? -ne 0 ]; then
      echo -e "${RED}Error: Failed to create project $project_id${NC}"
      return 1
    fi
    
    echo -e "${GREEN}Project $project_id created successfully.${NC}"
    
    # Link billing account if provided
    if [ -n "$BILLING_ACCOUNT_ID" ]; then
      echo -e "${BLUE}Linking billing account $BILLING_ACCOUNT_ID to project $project_id...${NC}"
      gcloud billing projects link $project_id --billing-account=$BILLING_ACCOUNT_ID >/dev/null 2>&1
      
      if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to link billing account to project $project_id${NC}"
        echo -e "${YELLOW}You will need to manually link a billing account to continue.${NC}"
        echo -e "${YELLOW}Visit: https://console.cloud.google.com/billing/linkedaccount?project=$project_id${NC}"
        read -p "Press Enter to continue once billing is linked..." -r
      else
        echo -e "${GREEN}Billing account linked successfully.${NC}"
      fi
    fi
  else
    echo -e "${GREEN}Project $project_id exists.${NC}"
    
    # Check billing status if project exists
    if [ -n "$BILLING_ACCOUNT_ID" ]; then
      local billing_info=$(gcloud billing projects describe $project_id --format="value(billingEnabled)" 2>/dev/null)
      
      if [ "$billing_info" != "True" ]; then
        echo -e "${YELLOW}Warning: Project $project_id does not have billing enabled.${NC}"
        echo -e "${YELLOW}Attempting to link billing account $BILLING_ACCOUNT_ID...${NC}"
        
        gcloud billing projects link $project_id --billing-account=$BILLING_ACCOUNT_ID >/dev/null 2>&1
        
        if [ $? -ne 0 ]; then
          echo -e "${RED}Error: Failed to link billing account.${NC}"
          echo -e "${YELLOW}You will need to manually link a billing account to continue.${NC}"
          echo -e "${YELLOW}Visit: https://console.cloud.google.com/billing/linkedaccount?project=$project_id${NC}"
          read -p "Press Enter to continue once billing is linked..." -r
        else
          echo -e "${GREEN}Billing account linked successfully.${NC}"
        fi
      else
        echo -e "${GREEN}Billing is already enabled for this project.${NC}"
      fi
    fi
  fi
  
  # Enable necessary APIs for the project
  enable_common_apis $project_id
  
  # Create terraform directory if it doesn't exist
  mkdir -p "terraform/$env"
  
  # Create terraform backend file
  cat > "terraform/$env/backend.tf" << EOF
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
EOF
  
  # Initialize Terraform
  echo -e "${BLUE}Initializing Terraform...${NC}"
  cd "terraform/$env" || return 1
  terraform init -reconfigure
  if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to initialize Terraform.${NC}"
    cd ../.. || return 1
    return 1
  fi
  
  # Prepare Terraform variables
  echo -e "${BLUE}Creating Terraform variables file...${NC}"
  cat > "terraform.tfvars" << EOF
project_id = "$project_id"
region = "$REGION"
developer = "$DEVELOPER_NAME"
environment = "$env"
EOF
  
  # Apply Terraform configuration
  echo -e "${BLUE}Applying Terraform configuration...${NC}"
  terraform apply -auto-approve
  terraform_result=$?
  
  if [ $terraform_result -ne 0 ]; then
    echo -e "${YELLOW}Warning: Terraform apply completed with errors.${NC}"
    echo -e "${YELLOW}This might be due to missing permissions or API enablement issues.${NC}"
    echo -e "${YELLOW}Attempting to continue with best-effort deployment...${NC}"
  else
    echo -e "${GREEN}Terraform apply completed successfully.${NC}"
  fi
  
  # Go back to project root
  cd ../.. || return 1
  
  # Setup Firebase
  if setup_firebase "$project_id"; then
    echo -e "${GREEN}Firebase setup completed successfully.${NC}"
  else
    echo -e "${YELLOW}Firebase setup was skipped. You may need to set it up manually.${NC}"
  fi
  
  # Set up GitHub Actions service account for CI/CD
  if setup_github_sa "$project_id" "$env"; then
    echo -e "${GREEN}GitHub Actions service account setup completed successfully.${NC}"
  else
    echo -e "${YELLOW}GitHub Actions service account setup failed. You may need to set it up manually.${NC}"
  fi

  # Print next steps
  echo -e "\n${GREEN}🚀 Environment bootstrapped successfully!${NC}"
  echo -e "${BLUE}Next steps:${NC}"
  echo -e "1. Set up GitHub secrets as described above"
  echo -e "2. Deploy the application: ./deploy.sh --$env"
}

# Loop through all requested environments and bootstrap them
for env in "${ENVIRONMENTS[@]}"; do
  echo -e "${BLUE}=== Bootstrapping $env environment ===${NC}"
  bootstrap_environment "$env"
  echo ""
done

# Create a .gitignore file or update it to exclude Firebase credentials
if [ -f ".gitignore" ]; then
  grep -q "firebase-admin-key" .gitignore || echo -e "\n# Firebase credentials\nfirebase-admin-key*.json\nsecrets/" >> .gitignore
  echo -e "${GREEN}Updated .gitignore to exclude Firebase credentials${NC}"
else
  echo -e "# Firebase credentials\nfirebase-admin-key*.json\nsecrets/" > .gitignore
  echo -e "${GREEN}Created .gitignore to exclude Firebase credentials${NC}"
fi

# Create secrets directory if it doesn't exist
mkdir -p secrets

# Create a service account for GitHub Actions if it doesn't exist
# Fix the service account creation to use the correct project ID format
if [[ " ${ENVIRONMENTS[*]} " =~ " dev " ]]; then
  # If dev environment is included, use the dev project for GitHub Actions
  GH_PROJECT_ID="${PROJECT_ID}-dev-${DEVELOPER_NAME}"
else
  # Otherwise use the first environment in the list
  FIRST_ENV=${ENVIRONMENTS[0]}
  GH_PROJECT_ID="${PROJECT_ID}-${FIRST_ENV}"
fi

SA_NAME="github-actions"
SA_EMAIL="${SA_NAME}@${GH_PROJECT_ID}.iam.gserviceaccount.com"

echo -e "${BLUE}Checking if GitHub Actions service account exists in project ${GH_PROJECT_ID}...${NC}"
sa_exists=$(gcloud iam service-accounts list --project=${GH_PROJECT_ID} --filter="email=${SA_EMAIL}" --format="value(email)" 2>/dev/null || echo "")

if [ -z "$sa_exists" ]; then
  echo -e "${GREEN}Creating GitHub Actions service account...${NC}"
  gcloud iam service-accounts create $SA_NAME \
    --project=${GH_PROJECT_ID} \
    --display-name="GitHub Actions Service Account" \
    --description="Used for GitHub Actions deployments" || echo -e "${YELLOW}Warning: Failed to create service account. It may already exist or you might not have permissions.${NC}"
  
  # Wait for the service account to be fully created
  sleep 5
  
  # Grant necessary roles for the service accounts
  for env in "${ENVIRONMENTS[@]}"; do
    if [ "$env" == "dev" ]; then
      actual_project_id="${PROJECT_ID}-${env}-${DEVELOPER_NAME}"
    else
      actual_project_id="${PROJECT_ID}-${env}"
    fi
    
    echo -e "${BLUE}Granting roles to service account for $env environment...${NC}"
    gcloud projects add-iam-policy-binding $actual_project_id \
      --member="serviceAccount:${SA_EMAIL}" \
      --role="roles/run.admin" || echo -e "${YELLOW}Warning: Failed to grant run.admin role. You might not have sufficient permissions.${NC}"
      
    gcloud projects add-iam-policy-binding $actual_project_id \
      --member="serviceAccount:${SA_EMAIL}" \
      --role="roles/storage.admin" || echo -e "${YELLOW}Warning: Failed to grant storage.admin role. You might not have sufficient permissions.${NC}"
      
    gcloud projects add-iam-policy-binding $actual_project_id \
      --member="serviceAccount:${SA_EMAIL}" \
      --role="roles/cloudbuild.builds.builder" || echo -e "${YELLOW}Warning: Failed to grant cloudbuild.builds.builder role. You might not have sufficient permissions.${NC}"
      
    gcloud projects add-iam-policy-binding $actual_project_id \
      --member="serviceAccount:${SA_EMAIL}" \
      --role="roles/iam.serviceAccountUser" || echo -e "${YELLOW}Warning: Failed to grant iam.serviceAccountUser role. You might not have sufficient permissions.${NC}"
  done
else
  echo -e "${YELLOW}GitHub Actions service account already exists. Skipping creation.${NC}"
fi

# Generate key for the service account
echo -e "${BLUE}Generating key for GitHub Actions service account...${NC}"
SA_KEY_FILE="secrets/github-actions-key.json"
gcloud iam service-accounts keys create $SA_KEY_FILE --project=${GH_PROJECT_ID} --iam-account=$SA_EMAIL || echo -e "${YELLOW}Warning: Failed to create service account key. You might not have sufficient permissions.${NC}"

# Continue only if the key was created
if [ -f "$SA_KEY_FILE" ]; then
  # Define the correct project IDs for each environment
  DEV_PROJECT_ID="${PROJECT_ID}-dev-${DEVELOPER_NAME}"
  STAGING_PROJECT_ID="${PROJECT_ID}-staging"
  PROD_PROJECT_ID="${PROJECT_ID}-prod"
  
  echo -e "${YELLOW}"
  echo "======================================================================================"
  echo "                 ACTION REQUIRED: GitHub Secrets Setup                              "
  echo "======================================================================================"
  echo -e "${NC}"
  echo "To enable CI/CD with GitHub Actions, add the following secrets to your repository:"
  echo ""
  echo "1. GCP_SA_KEY"
  echo "   Value: The content of the $SA_KEY_FILE file that was just created"
  echo "   (This file contains the service account credentials for GitHub Actions)"
  echo ""
  echo "2. DEV_PROJECT_ID"
  echo "   Value: ${DEV_PROJECT_ID}"
  echo ""
  echo "3. STAGING_PROJECT_ID"
  echo "   Value: ${STAGING_PROJECT_ID}"
  echo ""
  echo "4. PROD_PROJECT_ID"
  echo "   Value: ${PROD_PROJECT_ID}"
  echo ""
  echo "After adding these secrets, delete the $SA_KEY_FILE file for security reasons:"
  echo "   rm $SA_KEY_FILE"
  echo ""
  echo -e "${YELLOW}"
  echo "======================================================================================"
  echo -e "${NC}"
else
  echo -e "${YELLOW}Note: Service account key creation failed. You may need to create this manually.${NC}"
fi

echo -e "${GREEN}Bootstrap process complete!${NC}"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "1. Set up GitHub secrets as described above"
echo "2. Deploy the application: ./deploy.sh --all [--prod|--staging|--dev]"

# Helper function to set up GitHub Actions service account
setup_github_sa() {
  local project_id=$1
  local env=$2
  
  echo -e "${BLUE}Setting up GitHub Actions service account for $project_id...${NC}"
  SA_NAME="github-actions"
  SA_EMAIL="$SA_NAME@$project_id.iam.gserviceaccount.com"
  
  # Check if service account exists
  sa_exists=$(gcloud iam service-accounts list --project=$project_id --filter="email:$SA_EMAIL" --format="value(email)" 2>/dev/null || echo "")
  
  if [ -z "$sa_exists" ]; then
    # Create service account
    echo -e "${BLUE}Creating GitHub Actions service account...${NC}"
    gcloud iam service-accounts create $SA_NAME \
      --project=$project_id \
      --display-name="GitHub Actions Service Account" \
      --description="Service account for GitHub Actions deployments" >/dev/null 2>&1 || {
      echo -e "${RED}Failed to create service account for GitHub Actions. Check your permissions.${NC}"
      return 1
    }
    
    # Wait for the service account to be fully created
    sleep 5
    
    # Grant necessary roles to the service account
    echo -e "${BLUE}Granting roles to GitHub Actions service account...${NC}"
    GITHUB_ROLES=(
      "roles/run.admin" 
      "roles/iam.serviceAccountUser" 
      "roles/artifactregistry.admin" 
      "roles/firebase.admin"
      "roles/storage.admin"
      "roles/cloudbuild.builds.builder"
    )
    
    for role in "${GITHUB_ROLES[@]}"; do
      echo -e "${BLUE}Granting $role...${NC}"
      gcloud projects add-iam-policy-binding $project_id \
        --member="serviceAccount:$SA_EMAIL" \
        --role="$role" --quiet >/dev/null 2>&1 || {
        echo -e "${YELLOW}Warning: Failed to add role $role to service account. You might need to do this manually.${NC}"
      }
    done
  else
    echo -e "${GREEN}GitHub Actions service account already exists. Skipping creation.${NC}"
  fi
  
  # Check if key file already exists
  KEY_PATH="secrets/github-actions-key-${env}.json"
  mkdir -p "secrets"
  
  if [ ! -f "$KEY_PATH" ]; then
    echo -e "${BLUE}Creating key for GitHub Actions service account...${NC}"
    gcloud iam service-accounts keys create "$KEY_PATH" \
      --project=$project_id \
      --iam-account="$SA_EMAIL" >/dev/null 2>&1 || {
      echo -e "${RED}Failed to create key for service account. Check your permissions.${NC}"
      return 1
    }
    
    chmod 600 "$KEY_PATH"
    echo -e "${GREEN}Key created at $KEY_PATH${NC}"
    
    echo -e "${BLUE}Calculating BASE64 encoded version for GitHub secrets...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
      # macOS
      BASE64_KEY=$(base64 -i "$KEY_PATH" | tr -d '\n')
    else
      # Linux and others
      BASE64_KEY=$(base64 -w 0 "$KEY_PATH")
    fi
    
    echo -e "${BLUE}For GitHub repository, add the following secrets:${NC}"
    echo -e "GCP_PROJECT_ID: $project_id"
    echo -e "GCP_SA_KEY: $BASE64_KEY"
  else
    echo -e "${GREEN}Key file $KEY_PATH already exists. Skipping creation.${NC}"
  fi
} 