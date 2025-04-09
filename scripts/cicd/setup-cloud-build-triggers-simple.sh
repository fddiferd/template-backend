#!/bin/bash

# Set variables
DEV_PROJECT_ID="wedge-golf-dev"
STAGING_PROJECT_ID="wedge-golf-staging"
PROD_PROJECT_ID="wedge-golf-prod"

echo "Creating Cloud Build trigger for master branch in production project..."
gcloud builds triggers create manual \
  --project=$PROD_PROJECT_ID \
  --name="deploy-master" \
  --build-config="cloudbuilds/cloudbuild-prod.yaml" \
  --repo="https://github.com/fddiferd/fast-api-app" \
  --repo-type="GITHUB" \
  --branch="master"

echo "Creating Cloud Build trigger for staging branch in staging project..."
gcloud builds triggers create manual \
  --project=$STAGING_PROJECT_ID \
  --name="deploy-staging" \
  --build-config="cloudbuilds/cloudbuild-staging.yaml" \
  --repo="https://github.com/fddiferd/fast-api-app" \
  --repo-type="GITHUB" \
  --branch="staging"

echo "Creating Cloud Build trigger for dev branch in development project..."
gcloud builds triggers create manual \
  --project=$DEV_PROJECT_ID \
  --name="deploy-dev" \
  --build-config="cloudbuilds/cloudbuild-dev.yaml" \
  --repo="https://github.com/fddiferd/fast-api-app" \
  --repo-type="GITHUB" \
  --branch="dev"

echo "All triggers created successfully!"
echo ""
echo "Note: These are manual triggers that you can use to test deployments."
echo "To trigger a build, run:"
echo "gcloud builds triggers run deploy-master --branch=master --project=$PROD_PROJECT_ID"
echo "gcloud builds triggers run deploy-staging --branch=staging --project=$STAGING_PROJECT_ID"
echo "gcloud builds triggers run deploy-dev --branch=dev --project=$DEV_PROJECT_ID" 