#!/bin/bash

# Set variables
REPO_OWNER="fddiferd"
REPO_NAME="wedge-golf-backend"

# Function to create a Cloud Build trigger
create_trigger() {
  local environment=$1
  local branch=$2
  local project=$3

  echo "Creating trigger for $environment environment (branch: $branch, project: $project)"

  gcloud builds triggers create github \
    --repo-owner=$REPO_OWNER \
    --repo-name=$REPO_NAME \
    --branch-pattern="^$branch$" \
    --build-config=cloudbuilds/cloudbuild-$environment.yaml \
    --project=$project \
    --description="$environment Build Trigger"
}

# Create triggers for each environment
create_trigger "dev" "dev" "wedge-golf-dev"
create_trigger "staging" "staging" "wedge-golf-staging"
create_trigger "prod" "master" "wedge-golf-prod"

echo "Cloud Build triggers setup complete!" 