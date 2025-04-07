#!/bin/bash

# Set variables
DEV_PROJECT_ID="wedge-golf-dev"
STAGING_PROJECT_ID="wedge-golf-staging"
PROD_PROJECT_ID="wedge-golf-prod"
REPO_OWNER="fddiferd"  # Your GitHub username or organization
REPO_NAME="fast-api-app"  # Your repository name

# Function to create a Cloud Build trigger
create_trigger() {
  local project_id=$1
  local branch=$2
  local config_file=$3
  local description=$4

  echo "Creating trigger for $branch in project $project_id..."
  
  gcloud builds triggers create github \
    --project=$project_id \
    --repository="https://github.com/$REPO_OWNER/$REPO_NAME" \
    --name="deploy-$branch" \
    --description="$description" \
    --branch="^$branch$" \
    --build-config="$config_file"
  
  echo "Trigger created for $branch in project $project_id"
}

# Create triggers for each environment
create_trigger $DEV_PROJECT_ID "dev" "cloudbuilds/cloudbuild-dev.yaml" "Deploy to development environment when pushing to dev branch"
create_trigger $STAGING_PROJECT_ID "staging" "cloudbuilds/cloudbuild-staging.yaml" "Deploy to staging environment when pushing to staging branch"
create_trigger $PROD_PROJECT_ID "master" "cloudbuilds/cloudbuild-prod.yaml" "Deploy to production environment when pushing to master branch"

echo "All triggers created successfully!"
echo ""
echo "To test deployments, create branches with ./init-git-branches.sh and push to them:"
echo "- Push to 'dev' branch → deploys to Development"
echo "- Push to 'staging' branch → deploys to Staging"
echo "- Push to 'master' branch → deploys to Production" 