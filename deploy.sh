#!/bin/bash
set -e

# Load environment variables
source .env

# Check if GCP_PROJECT_ID is set
if [ -z "$GCP_PROJECT_ID" ]; then
  echo "Error: GCP_PROJECT_ID is not set in .env"
  exit 1
fi

# Check the mode
if [ -z "$MODE" ]; then
  echo "MODE not set in .env, defaulting to dev"
  MODE="dev"
fi

# Set project name based on mode
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

# Service name
SERVICE_NAME="wedge-api"
REGION="us-central1"
ARTIFACT_REPO="${REGION}-docker.pkg.dev/${PROJECT_NAME}/wedge-api"

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