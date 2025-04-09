#!/bin/bash
set -e

# Load environment variables
source .env

# Load config values
GCP_PROJECT_ID=$(grep -oP '^gcp_project_id: str = \K.*(?=\s*$)' config | tr -d "'")
SERVICE_NAME=$(grep -oP '^service_name: str = \K.*(?=\s*$)' config | tr -d "'")
REPO_NAME=$(grep -oP '^repo_name: str = \K.*(?=\s*$)' config | tr -d "'")
REGION=$(grep -oP '^region: str = \K.*(?=\s*$)' config | tr -d "'")

# Check if PROJECT_ID from config is available
if [ -z "$GCP_PROJECT_ID" ]; then
  echo "Error: gcp_project_id is not set in config file"
  exit 1
fi

# Use PROJECT_ID from .env if specified, otherwise use from config
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID="$GCP_PROJECT_ID"
fi

# Check the mode
if [ -z "$MODE" ]; then
  echo "MODE not set in .env, defaulting to dev"
  MODE="dev"
fi

# Set project name based on mode
if [ "$MODE" == "dev" ]; then
  if [ -z "$DEV_SCHEMA_NAME" ]; then
    echo "DEV_SCHEMA_NAME not set in .env, required for dev mode"
    exit 1
  fi
  PROJECT_NAME="${PROJECT_ID}-${DEV_SCHEMA_NAME}"
elif [ "$MODE" == "staging" ]; then
  PROJECT_NAME="${PROJECT_ID}-staging"
elif [ "$MODE" == "prod" ]; then
  PROJECT_NAME="${PROJECT_ID}-prod"
else
  echo "Invalid MODE: $MODE. Must be dev, staging, or prod."
  exit 1
fi

# Check if project exists
if ! gcloud projects describe "$PROJECT_NAME" &> /dev/null; then
  echo "Error: Project $PROJECT_NAME does not exist. Run bootstrap.sh first."
  exit 1
fi

# Build and deploy service
ARTIFACT_REPO="${REGION}-docker.pkg.dev/${PROJECT_NAME}/${REPO_NAME}"

echo "Building and deploying to project: $PROJECT_NAME"
echo "Mode: $MODE"

# Build the Docker image
echo "Building Docker image..."
IMAGE_TAG="${ARTIFACT_REPO}/${SERVICE_NAME}:latest"
docker build -t "$IMAGE_TAG" .

# Configure Docker to use gcloud as a credential helper
echo "Configuring Docker authentication..."
gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Push the image to Artifact Registry
echo "Pushing image to Artifact Registry..."
docker push "$IMAGE_TAG"

# Deploy to Cloud Run
echo "Deploying to Cloud Run..."
gcloud run deploy "$SERVICE_NAME" \
  --image="$IMAGE_TAG" \
  --platform=managed \
  --region="$REGION" \
  --allow-unauthenticated \
  --project="$PROJECT_NAME"

echo "Deployment complete!"
echo "Service URL: $(gcloud run services describe $SERVICE_NAME --platform=managed --region=$REGION --project=$PROJECT_NAME --format='value(status.url)')" 