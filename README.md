# Wedge Golf Backend Complete Production-Ready Guide

This repository contains everything needed to set up, deploy, and maintain a FastAPI backend integrated with Firestore using Firebase Admin SDK, leveraging Terraform for infrastructure setup on Google Cloud Platform (GCP), and Google Cloud Build for CI/CD.

## Repository Structure

```
wedge-backend/
├── Dockerfile                   # Container configuration
├── .dockerignore
├── cloudbuilds/                 # Cloud Build configuration files
│   ├── cloudbuild.yaml          # Main Cloud Build configuration
│   ├── cloudbuild-dev.yaml      # Dev environment configuration
│   ├── cloudbuild-staging.yaml  # Staging environment configuration
│   └── cloudbuild-prod.yaml     # Production environment configuration
├── service_accounts/            # Firebase service account files (do not commit)
│   ├── firebase-dev.json
│   ├── firebase-staging.json
│   └── firebase-prod.json
├── setup-cloud-build-triggers.sh # Script to set up Cloud Build triggers
├── src/
│   ├── __init__.py
│   ├── app.py                   # FastAPI entry point
│   └── database.py              # Database connection settings
├── pyproject.toml               # Python dependencies
├── terraform/
│   ├── bootstrap/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   └── cicd/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars
├── .env (do not commit)
└── tests/
    └── test_firestore_e2e.py
```

## Initial Setup

### Step 1: Install Dependencies

```bash
poetry install
```

### Step 2: Firebase Service Accounts

Place your Firebase service account JSON files in the `service_accounts` directory:
- `service_accounts/firebase-dev.json`
- `service_accounts/firebase-staging.json`
- `service_accounts/firebase-prod.json`

## Terraform Setup

### Terraform Part 1: Bootstrap (Firebase Project Creation)

Configure your project IDs in `terraform/bootstrap/terraform.tfvars`:

```hcl
project_ids = {
  dev     = "your-dev-project-id"
  staging = "your-staging-project-id"
  prod    = "your-prod-project-id"
}
```

Run Terraform:

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

This step creates your Firebase/GCP projects.

### Terraform Part 2: CI/CD (Ongoing Infrastructure)

Set your environment in `terraform/cicd/terraform.tfvars`:

```hcl
environment = "dev"  # or staging/prod
```

Run Terraform:

```bash
cd terraform/cicd
terraform init
terraform apply
```

This step sets up ongoing infrastructure (Cloud Run, Artifact Registry, Firestore permissions).

## Local Development

Create a `.env` file at the project root:

```env
ENVIRONMENT=dev # or staging/prod
# FIREBASE_CRED_PATH=service_accounts/firebase-dev.json (optional override)
```

Run locally:

```bash
uvicorn src.app:app --reload
```

## Docker Build and Deploy

Authenticate with GCP and Artifact Registry:

```bash
gcloud auth configure-docker us-central1-docker.pkg.dev
docker build -t us-central1-docker.pkg.dev/<GCP_PROJECT_ID>/fastapi-app/fastapi:latest .
docker push us-central1-docker.pkg.dev/<GCP_PROJECT_ID>/fastapi-app/fastapi:latest
```

## CI/CD with Google Cloud Build

The repository includes a script to automatically set up Cloud Build triggers for all environments. The triggers are already configured with the correct repository information:

- Repository Owner: `fddiferd`
- Repository Name: `wedge-golf`

To set up the Cloud Build triggers for automatic deployment:

1. Make sure you're authenticated with gcloud:
   ```bash
   gcloud auth login
   ```

2. Run the setup script:
   ```bash
   ./setup-cloud-build-triggers.sh
   ```

### Cloud Build Configuration Files

Each environment has its own Cloud Build configuration file in the `cloudbuilds` directory:

- **cloudbuilds/cloudbuild-dev.yaml**: Configuration for the dev environment
- **cloudbuilds/cloudbuild-staging.yaml**: Configuration for the staging environment
- **cloudbuilds/cloudbuild-prod.yaml**: Configuration for the production environment

These files specify:
- Building the Docker container
- Pushing to Container Registry
- Deploying to Cloud Run with unauthenticated access
- Setting the appropriate environment variables

### Git Branch-Based Deployment

The CI/CD pipeline is set up to deploy automatically based on the Git branch:

1. **dev branch**: Pushes to this branch will deploy to the development environment
   ```bash
   git checkout dev
   git commit -m "Your dev changes"
   git push origin dev
   ```

2. **staging branch**: Pushes to this branch will deploy to the staging environment
   ```bash
   git checkout staging
   git commit -m "Your staging changes"
   git push origin staging
   ```

3. **master/main branch**: Pushes to this branch will deploy to the production environment
   ```bash
   git checkout master
   git commit -m "Your production changes"
   git push origin master
   ```

### Manual Deployment

You can also deploy manually using the following commands:

```bash
# Build and deploy to development
gcloud builds submit --config=cloudbuilds/cloudbuild-dev.yaml --project=wedge-golf-dev

# Build and deploy to staging
gcloud builds submit --config=cloudbuilds/cloudbuild-staging.yaml --project=wedge-golf-staging

# Build and deploy to production
gcloud builds submit --config=cloudbuilds/cloudbuild-prod.yaml --project=wedge-golf-prod
```

### Testing Deployment to Different Environments

To set up the Git branches for deployment testing, you can use the provided script:

```bash
./init-git-branches.sh
```

This script will:
1. Create dev, staging, and master branches if they don't exist
2. Show instructions for testing deployments to each environment

To test deployment to different environments:

1. **Testing Dev Deployment**:
   ```bash
   # Switch to dev branch
   git checkout dev
   # Make changes, commit them
   git add .
   git commit -m "Test dev deployment"
   # Push to dev branch
   git push origin dev
   ```

2. **Testing Staging Deployment**:
   ```bash
   # Create and switch to staging branch
   git checkout -b staging
   # Make changes, commit them
   git add .
   git commit -m "Test staging deployment"
   # Push to staging branch
   git push origin staging
   ```

3. **Testing Production Deployment**:
   ```bash
   # Create and switch to master branch (if not already on it)
   git checkout master
   # Make changes, commit them
   git add .
   git commit -m "Test production deployment"
   # Push to master branch
   git push origin master
   ```

### Accessing the Deployed API

After deployment, your API will be available at the Cloud Run URL provided in the deployment output. The endpoints will be:

- Root endpoint: `https://<cloud-run-url>/`
- Health check: `https://<cloud-run-url>/health`
- API status: `https://<cloud-run-url>/api/v1/status`

Enjoy developing your Wedge Golf backend!