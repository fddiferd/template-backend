#!/bin/bash
set -e

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
  else
    echo -e "${YELLOW}GitHub Actions service account already exists. Skipping creation.${NC}"
  fi

  # Generate key for the GitHub Actions service account
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

# Function to bootstrap a specific environment
bootstrap_environment() {
  local env=$1
  local actual_project_id
  
  # Use consistent project ID format for all environments
  # For dev environments, include the developer name
  if [ "$env" == "dev" ]; then
    actual_project_id="${PROJECT_ID}-${env}-${DEVELOPER_NAME}"
  else
    actual_project_id="${PROJECT_ID}-${env}"
  fi
  
  echo -e "${BLUE}Checking if project $actual_project_id exists...${NC}"
  project_exists=$(gcloud projects list --format="value(projectId)" --filter="projectId=$actual_project_id" 2>/dev/null || echo "")
  
  if [ -n "$project_exists" ]; then
    echo -e "${YELLOW}Project $actual_project_id already exists. Continuing with existing project...${NC}"
    
    # Check if the user has sufficient permissions on the project
    echo -e "${BLUE}Checking permissions on project $actual_project_id...${NC}"
    if ! gcloud projects get-iam-policy $actual_project_id &>/dev/null; then
      echo -e "${YELLOW}Warning: You don't have sufficient permissions on project $actual_project_id.${NC}"
      if [ "$SKIP_CONFIRM" != "true" ]; then
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
          echo "Skipping environment $env."
          return
        fi
      fi
    else
      echo -e "${GREEN}Permission check passed! Proceeding with the existing project.${NC}"
    fi
    
    # Make sure billing is linked for existing projects
    echo -e "${BLUE}Ensuring billing account is linked for project $actual_project_id...${NC}"
    gcloud billing projects link $actual_project_id --billing-account=$BILLING_ACCOUNT_ID || echo -e "${YELLOW}Warning: Failed to link billing account. Project may already be linked or you might not have sufficient permissions.${NC}"
  else
    echo -e "${GREEN}Project $actual_project_id does not exist. Will create new project.${NC}"
    
    # Create the project manually first
    echo -e "${BLUE}Creating project $actual_project_id...${NC}"
    gcloud projects create $actual_project_id --name="${PROJECT_NAME}-${env}" || echo -e "${YELLOW}Warning: Failed to create project. It may already exist or you might not have sufficient permissions.${NC}"
    
    # Link the billing account
    echo -e "${BLUE}Linking billing account for project $actual_project_id...${NC}"
    gcloud billing projects link $actual_project_id --billing-account=$BILLING_ACCOUNT_ID || echo -e "${YELLOW}Warning: Failed to link billing account. You might not have sufficient permissions.${NC}"
  fi
  
  # Initialize and apply Terraform for this environment
  echo -e "${BLUE}Initializing Terraform for $env environment...${NC}"
  cd terraform
  terraform init
  
  echo -e "${BLUE}Applying Terraform configuration for $env environment...${NC}"
  set +e  # Don't exit on error
  terraform apply \
    -var "project_id=$PROJECT_ID" \
    -var "environment=$env" \
    -var "developer_name=$DEVELOPER_NAME" \
    -var "billing_account_id=$BILLING_ACCOUNT_ID" \
    -auto-approve
  
  terraform_exit_code=$?
  
  if [ $terraform_exit_code -ne 0 ]; then
    echo -e "${YELLOW}Terraform encountered errors with exit code $terraform_exit_code.${NC}"
    echo -e "${YELLOW}This is often expected when some resources already exist or there are permission issues.${NC}"
    
    # Try to enable APIs manually if terraform fails to do so
    echo -e "${BLUE}Attempting to enable required APIs manually...${NC}"
    gcloud services enable iam.googleapis.com \
      cloudkms.googleapis.com \
      firestore.googleapis.com \
      run.googleapis.com \
      artifactregistry.googleapis.com \
      cloudbuild.googleapis.com \
      logging.googleapis.com \
      monitoring.googleapis.com \
      compute.googleapis.com \
      secretmanager.googleapis.com \
      --project $actual_project_id || echo -e "${YELLOW}Warning: Failed to enable some APIs. You might need to enable them manually.${NC}"
    
    echo -e "${YELLOW}Trying to retrieve outputs anyway...${NC}"
  fi
  
  # Try to get outputs even if there was an error
  set +e
  TF_PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || echo "$actual_project_id")
  TF_BACKEND_URL=$(terraform output -raw backend_url 2>/dev/null || echo "Not available yet")
  TF_FRONTEND_URL=$(terraform output -raw frontend_url 2>/dev/null || echo "Not available yet")
  set -e
  
  if [ $terraform_exit_code -eq 0 ]; then
    echo -e "${GREEN}Infrastructure for $env environment provisioned successfully!${NC}"
  else
    echo -e "${YELLOW}Infrastructure provisioning may be incomplete, but the environment should be usable.${NC}"
    echo -e "${YELLOW}You can rerun this script or fix the issues manually.${NC}"
  fi
  
  echo -e "${GREEN}Project ID:${NC} $TF_PROJECT_ID"
  echo -e "${GREEN}Backend URL:${NC} $TF_BACKEND_URL"
  echo -e "${GREEN}Frontend URL:${NC} $TF_FRONTEND_URL"
  
  # Return to root directory
  cd ..
  
  # Update .env file with project ID
  if [ "$env" == "dev" ] && [ "$TF_PROJECT_ID" != "unknown" ]; then
    if [ -f ".env" ]; then
      sed -i "" "s|GCP_PROJECT_ID=.*|GCP_PROJECT_ID=$TF_PROJECT_ID|g" .env 2>/dev/null || sed -i "s|GCP_PROJECT_ID=.*|GCP_PROJECT_ID=$TF_PROJECT_ID|g" .env
    fi
  fi
  
  # Return 0 to continue regardless of Terraform exit code
  return 0
}

# Loop through all requested environments and bootstrap them
for env in "${ENVIRONMENTS[@]}"; do
  echo -e "${BLUE}=== Bootstrapping $env environment ===${NC}"
  bootstrap_environment "$env"
  echo ""
done

# After project creation and resource provisioning but before creating GitHub keys
# For each environment that was bootstrapped
for env in "${ENVIRONMENTS[@]}"; do
  local actual_project_id
  
  # Set the project ID based on environment
  if [ "$env" == "dev" ]; then
    actual_project_id="${PROJECT_ID}-${env}-${DEVELOPER_NAME}"
  else
    actual_project_id="${PROJECT_ID}-${env}"
  fi
  
  echo -e "${BLUE}Setting up Firebase for $actual_project_id...${NC}"
  
  # Run Firebase bootstrap script if available
  if [ -f "./scripts/bootstrap_firebase.sh" ]; then
    ./scripts/bootstrap_firebase.sh --$env --yes
    if [ $? -ne 0 ]; then
      echo -e "${YELLOW}Warning: Firebase setup had some issues. See logs above.${NC}"
    fi
  else
    echo -e "${YELLOW}Warning: Firebase bootstrap script not found.${NC}"
    echo -e "${YELLOW}Creating scripts directory and Firebase bootstrap script...${NC}"
    
    # Create scripts directory if it doesn't exist
    mkdir -p scripts
    
    # Create Firebase bootstrap script
    cat > ./scripts/bootstrap_firebase.sh << 'EOF'
#!/bin/bash

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="dev"
SKIP_CONFIRMATION=false

# Function to display help message
show_help() {
  echo "Firebase Bootstrap Script"
  echo "========================="
  echo "This script sets up Firebase resources for your project."
  echo
  echo "Usage: ./bootstrap_firebase.sh [options]"
  echo
  echo "Options:"
  echo "  --prod            Bootstrap Firebase for production environment"
  echo "  --staging         Bootstrap Firebase for staging environment"
  echo "  --dev             Bootstrap Firebase for development environment (default)"
  echo "  --all             Bootstrap Firebase for all environments"
  echo "  --yes             Skip confirmation prompts"
  echo "  --help            Show this help message"
  echo
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prod)
      ENVIRONMENT="prod"
      shift
      ;;
    --staging)
      ENVIRONMENT="staging"
      shift
      ;;
    --dev)
      ENVIRONMENT="dev"
      shift
      ;;
    --all)
      ENVIRONMENT="all"
      shift
      ;;
    --yes)
      SKIP_CONFIRMATION=true
      shift
      ;;
    --help)
      show_help
      exit 0
      ;;
    *)
      echo -e "${RED}Error: Unknown option $1${NC}"
      show_help
      exit 1
      ;;
  esac
done

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check for required tools
for cmd in gcloud firebase jq; do
  if ! command_exists "$cmd"; then
    echo -e "${RED}Error: $cmd is not installed.${NC}"
    echo "Please install it and try again."
    exit 1
  fi
done

# Check if user is logged in to gcloud and firebase
echo "Checking gcloud authentication..."
gcloud auth list --filter=status:ACTIVE --format="value(account)" > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "${YELLOW}You need to authenticate with gcloud first.${NC}"
  gcloud auth login
fi

echo "Checking Firebase authentication..."
firebase login:list > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "${YELLOW}You need to authenticate with Firebase first.${NC}"
  firebase login
fi

# Create secrets directory if it doesn't exist
mkdir -p secrets

# Function to bootstrap Firebase for a specific environment
bootstrap_firebase() {
  local env=$1
  local developer=""
  
  # Determine project ID based on environment
  if [ "$env" == "dev" ]; then
    # For dev, include developer name
    if [ -f .env ]; then
      source .env
      developer=${DEVELOPER_NAME:-$(whoami)}
    else
      developer=$(whoami)
    fi
    PROJECT_ID="${PROJECT_ID:-test-wedge-golf}-$env-$developer"
  else
    PROJECT_ID="${PROJECT_ID:-test-wedge-golf}-$env"
  fi
  
  echo -e "${GREEN}Bootstrapping Firebase for project: $PROJECT_ID${NC}"
  
  # Check if project exists
  gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo -e "${RED}Error: GCP project $PROJECT_ID does not exist.${NC}"
    echo "Please run the main deploy script first to create the project."
    return 1
  fi
  
  # Enable required APIs if not already enabled
  echo "Enabling required APIs..."
  gcloud services enable firebase.googleapis.com --project="$PROJECT_ID"
  gcloud services enable firestore.googleapis.com --project="$PROJECT_ID"
  gcloud services enable firebaserules.googleapis.com --project="$PROJECT_ID"
  
  # Check if project is already registered with Firebase
  firebase projects:list | grep "$PROJECT_ID" > /dev/null
  if [ $? -ne 0 ]; then
    echo "Project not found in Firebase - adding it now..."
    firebase projects:addfirebase "$PROJECT_ID"
  else
    echo "Project already registered with Firebase."
  fi
  
  # Initialize Firestore Database
  echo "Setting up Firestore database..."
  gcloud firestore databases create --location=us-central --project="$PROJECT_ID" || true
  
  # Create Firebase service account if it doesn't exist
  echo "Setting up Firebase Admin SDK service account..."
  SA_EMAIL="firebase-admin@$PROJECT_ID.iam.gserviceaccount.com"
  
  # Check if service account exists
  gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "Creating Firebase Admin service account..."
    gcloud iam service-accounts create firebase-admin \
      --display-name="Firebase Admin" \
      --project="$PROJECT_ID"
  fi
  
  # Grant necessary roles to the service account
  echo "Granting IAM roles to Firebase service account..."
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/datastore.user"
    
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/firebase.admin"
    
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/firebase.sdkAdminServiceAgent"
  
  # Create a key for the service account if needed
  CREDENTIALS_FILE="secrets/firebase-admin-key-$env.json"
  if [ ! -f "$CREDENTIALS_FILE" ]; then
    echo "Creating service account key..."
    gcloud iam service-accounts keys create "$CREDENTIALS_FILE" \
      --iam-account="$SA_EMAIL" \
      --project="$PROJECT_ID"
    
    # Set appropriate permissions on the credentials file
    chmod 600 "$CREDENTIALS_FILE"
    echo "Credentials saved to $CREDENTIALS_FILE with restricted permissions"
  fi
  
  # Check if backend service account exists before giving it access
  BACKEND_SA="backend-sa@$PROJECT_ID.iam.gserviceaccount.com"
  gcloud iam service-accounts describe "$BACKEND_SA" --project="$PROJECT_ID" >/dev/null 2>&1
  
  # Upload the key to Secret Manager
  echo "Uploading Firebase credentials to Secret Manager..."
  gcloud secrets create firebase-credentials \
    --data-file="$CREDENTIALS_FILE" \
    --project="$PROJECT_ID" 2>/dev/null || \
  gcloud secrets versions add firebase-credentials \
    --data-file="$CREDENTIALS_FILE" \
    --project="$PROJECT_ID"
  
  # Grant Secret Manager access to service accounts if backend SA exists
  if [ $? -eq 0 ]; then
    gcloud secrets add-iam-policy-binding firebase-credentials \
      --member="serviceAccount:$BACKEND_SA" \
      --role="roles/secretmanager.secretAccessor" \
      --project="$PROJECT_ID" 2>/dev/null || true
  else
    echo "Note: Backend service account does not exist yet. You will need to run deploy.sh to create it."
  fi
  
  # Create a sample document in Firestore if this is dev environment
  if [ "$env" == "dev" ]; then
    echo "Creating sample data in Firestore..."
    TIMESTAMP=$(date +"%Y-%m-%dT%H:%M:%S")
    
    # This is the proper format for Firestore REST API
    SAMPLE_DATA="{\"fields\":{\"first_name\":{\"stringValue\":\"Sample\"},\"last_name\":{\"stringValue\":\"User\"},\"email\":{\"stringValue\":\"sample@example.com\"},\"created_at\":{\"stringValue\":\"$TIMESTAMP\"},\"updated_at\":{\"stringValue\":\"$TIMESTAMP\"}}}"
    
    # Using curl with the service account key for authentication
    # First get access token
    TOKEN=$(gcloud auth print-access-token)
    
    # Create sample document in Firestore
    curl -X POST \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "$SAMPLE_DATA" \
      "https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/customers?documentId=sample-user"
  fi
  
  echo -e "${GREEN}Firebase bootstrap completed for $PROJECT_ID.${NC}"
  echo -e "${YELLOW}Important: Make sure the backend service is using the credentials at secrets/firebase-admin-key-$env.json${NC}"
  echo -e "${YELLOW}These credentials are also uploaded to Secret Manager as 'firebase-credentials'${NC}"
}

# Process based on selected environment
if [ "$ENVIRONMENT" == "all" ]; then
  # Confirm if not using --yes
  if [ "$SKIP_CONFIRMATION" != "true" ]; then
    echo -e "${YELLOW}You are about to bootstrap Firebase for ALL environments (dev, staging, prod).${NC}"
    echo -e "${YELLOW}This may incur costs and affect production services.${NC}"
    read -p "Do you want to continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 0
    fi
  fi
  
  # Bootstrap all environments
  bootstrap_firebase "dev"
  bootstrap_firebase "staging"
  bootstrap_firebase "prod"
else
  # Confirm if not using --yes and not dev
  if [ "$SKIP_CONFIRMATION" != "true" ] && [ "$ENVIRONMENT" != "dev" ]; then
    echo -e "${YELLOW}You are about to bootstrap Firebase for the $ENVIRONMENT environment.${NC}"
    echo -e "${YELLOW}This may incur costs or affect services.${NC}"
    read -p "Do you want to continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 0
    fi
  fi
  
  # Bootstrap specific environment
  bootstrap_firebase "$ENVIRONMENT"
fi

echo -e "${GREEN}Firebase bootstrap process completed.${NC}"
echo -e "${YELLOW}Note: Service account keys have been saved to the secrets/ directory${NC}"
echo -e "${YELLOW}Make sure to add this directory to your .gitignore file${NC}"
EOF
    
    # Make the script executable
    chmod +x ./scripts/bootstrap_firebase.sh
    echo -e "${GREEN}Created Firebase bootstrap script at ./scripts/bootstrap_firebase.sh${NC}"
    
    # Run the newly created script
    ./scripts/bootstrap_firebase.sh --$env --yes
    if [ $? -ne 0 ]; then
      echo -e "${YELLOW}Warning: Firebase setup had some issues. See logs above.${NC}"
    fi
  fi
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