#!/bin/bash
set -e

echo "===================================================================="
echo "            FastAPI Application Deployment Tool                      "
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
# SECTION 2: PROJECT IDENTIFICATION
#==========================================================================
echo
echo "PROJECT IDENTIFICATION"
echo "---------------------"

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

echo "Deploying to project: $PROJECT_NAME (Environment: $MODE)"

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

# Check if project exists
if ! gcloud projects describe "$PROJECT_NAME" &> /dev/null; then
  echo "❌ Error: Project $PROJECT_NAME does not exist. Run bootstrap.sh first."
  exit 1
fi
echo "✅ Project verified"

#==========================================================================
# SECTION 3: ARTIFACT REGISTRY SETUP
#==========================================================================
echo
echo "ARTIFACT REGISTRY SETUP"
echo "----------------------"

# Check if we have Artifact Registry permissions
if ! gcloud artifacts repositories list --project="$PROJECT_NAME" --location="$REGION" &> /dev/null; then
  echo "❌ Error: You don't have Artifact Registry permissions for project $PROJECT_NAME"
  echo "Please run the bootstrap script again to set up proper permissions:"
  echo "./scripts/setup/bootstrap.sh"
  exit 1
fi

# Set up Artifact Registry repository if it doesn't exist
REPO_EXISTS=$(gcloud artifacts repositories list --project=$PROJECT_NAME --location=$REGION --filter="name:$REPO_NAME" --format="value(name)")
if [ -z "$REPO_EXISTS" ]; then
  echo "Creating Artifact Registry repository: $REPO_NAME in $REGION..."
  gcloud artifacts repositories create $REPO_NAME \
    --project=$PROJECT_NAME \
    --repository-format=docker \
    --location=$REGION \
    --description="Docker repository for $SERVICE_NAME"
  
  if [ $? -ne 0 ]; then
    echo "❌ Error creating Artifact Registry repository."
    echo "This may be due to insufficient permissions."
    echo "Try running the bootstrap script again: ./scripts/setup/bootstrap.sh"
    exit 1
  fi
  
  echo "✅ Artifact Registry repository created"
else
  echo "✅ Artifact Registry repository already exists"
fi

#==========================================================================
# SECTION 4: CONTAINER BUILD
#==========================================================================
echo
echo "BUILDING CONTAINER"
echo "-----------------"

# Build container image
IMAGE_NAME="${REGION}-docker.pkg.dev/${PROJECT_NAME}/${REPO_NAME}/${SERVICE_NAME}"
TAG=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")

echo "Building container image: $IMAGE_NAME:$TAG"
docker build --platform linux/amd64 -t $IMAGE_NAME:$TAG -f docker/Dockerfile .
echo "✅ Container build completed"

#==========================================================================
# SECTION 5: ARTIFACT REGISTRY PUSH
#==========================================================================
echo
echo "PUSHING TO ARTIFACT REGISTRY"
echo "---------------------------"

# Push container image
echo "Authenticating with GCP..."
gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

echo "Pushing container image to ${REGION}-docker.pkg.dev..."
docker push $IMAGE_NAME:$TAG
echo "✅ Container pushed to Artifact Registry"

#==========================================================================
# SECTION 6: CLOUD RUN DEPLOYMENT
#==========================================================================
echo
echo "DEPLOYING TO CLOUD RUN"
echo "---------------------"

# Deploy to Cloud Run
echo "Deploying to Cloud Run in $REGION..."
gcloud run deploy $SERVICE_NAME \
  --image $IMAGE_NAME:$TAG \
  --platform managed \
  --region $REGION \
  --allow-unauthenticated \
  --set-env-vars="ENVIRONMENT=$MODE" \
  --project $PROJECT_NAME

# Get deployed URL
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --platform managed --region $REGION --project $PROJECT_NAME --format 'value(status.url)')

echo "✅ Deployment completed successfully!"
echo "Service URL: $SERVICE_URL"

#==========================================================================
# SECTION 7: VERIFICATION
#==========================================================================
echo
echo "VERIFYING DEPLOYMENT"
echo "-------------------"

# Test the deployed service
echo "Testing the deployed service..."
if curl -s $SERVICE_URL/health | grep -q "ok"; then
  echo "✅ Service is healthy"
else
  echo "⚠️ Service health check failed. Please check your application logs."
fi

echo
echo "===================================================================="
echo "Deployment to $PROJECT_NAME ($MODE environment) complete!"
echo "You can access your application at: $SERVICE_URL"
echo "====================================================================" 