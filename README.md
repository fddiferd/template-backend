# Backend Template - FastAPI Application with GCP Deployment

This repository contains a FastAPI application with automated infrastructure for deployment to Google Cloud Platform using Cloud Run, Artifact Registry, and Firebase integration.

## Table of Contents

- [Overview](#overview)
- [Project Structure](#project-structure)
- [Setup and Installation](#setup-and-installation)
  - [Prerequisites](#prerequisites)
  - [GCP Permissions](#gcp-permissions)
  - [Repository Setup](#repository-setup)
  - [Environment Configuration](#environment-configuration)
  - [Dependencies Installation](#dependencies-installation)
- [Core Workflows](#core-workflows)
  - [Initial Verification](#initial-verification)
  - [Bootstrapping Your Project](#bootstrapping-your-project)
  - [Deploying the Application](#deploying-the-application)
  - [Accessing Your API](#accessing-your-api)
- [CI/CD Pipeline](#cicd-pipeline)
  - [Automated Deployments](#automated-deployments)
  - [Testing CI/CD Events](#testing-cicd-events)
  - [Pipeline Verification](#pipeline-verification)
- [Development Guide](#development-guide)
  - [Local Development](#local-development)
  - [Docker Development](#docker-development)
  - [Git Workflow](#git-workflow)
- [Features](#features)
  - [Firestore Integration](#firestore-integration)
  - [GitHub Integration](#github-integration)
- [Troubleshooting](#troubleshooting)
  - [Common Setup Issues](#common-setup-issues)
  - [Deployment Issues](#deployment-issues)
  - [Manual Terraform Operations](#manual-terraform-operations)
- [Reference](#reference)
  - [Useful Commands](#useful-commands)
  - [Compatibility Notes](#compatibility-notes)

## Overview

This template provides a complete setup for building and deploying a FastAPI application to Google Cloud Platform. Key features include:

- **Automated Infrastructure**: Terraform configurations for GCP resources
- **CI/CD Pipeline**: Automatic deployments via Cloud Build
- **Firebase Integration**: Firestore database with both Native and Datastore modes
- **Developer-Friendly**: Easy setup for individual development environments
- **Cross-Platform**: Works on macOS, Linux, and other Unix-like systems

## Project Structure

- `app/`: FastAPI application code
- `config`: Project-level configuration (shared across all developers)
- `docker/`: Docker-related files
  - `Dockerfile`: Container definition 
  - `.dockerignore`: Files to exclude from Docker builds
- `scripts/`: Scripts for setup, deployment, and testing
  - `cicd/`: CI/CD scripts
    - `deploy.sh`: Manual deployment script
    - `simulate_cicd_events.sh`: Tool for testing CI/CD events
    - `cloudbuild.yaml`: Cloud Build configuration
  - `setup/`: Setup scripts
    - `bootstrap.sh`: Creates and configures GCP projects
    - `init-git-branches.sh`: Initialize Git branches
  - `test/`: Testing scripts
    - `run_tests.sh`: Run test suites
    - `verify_library.sh`: Comprehensive verification
- `terraform/`: Infrastructure as Code using Terraform
  - `bootstrap/`: Initial GCP project setup
  - `cicd/`: CI/CD and deployment configuration
- `tests/`: Application tests
- Shortcut Scripts:
  - `bootstrap`: Wrapper for ./scripts/setup/bootstrap.sh
  - `deploy`: Wrapper for ./scripts/cicd/deploy.sh
  - `simulate`: Wrapper for ./scripts/cicd/simulate_cicd_events.sh
  - `get-api-url`: Helper to get your deployed API URL
- Configuration:
  - `.env`: Developer-specific environment variables
  - `pyproject.toml`: Python project definition and dependencies

## Setup and Installation

### Prerequisites

Before starting, ensure you have the following:

1. **Google Cloud SDK** installed and configured
   ```bash
   # Install Google Cloud SDK
   curl https://sdk.cloud.google.com | bash
   # Initialize Google Cloud SDK
   gcloud init
   ```

2. **Terraform** installed (for infrastructure management)
   ```bash
   # On macOS with Homebrew
   brew install terraform
   # On Linux
   sudo apt-get install terraform
   ```

3. **Python 3.11+** installed
   ```bash
   # Install Python
   # macOS
   brew install python@3.11
   # Ubuntu
   sudo apt-get install python3.11
   ```

4. **Docker** installed (for local testing and builds)

### GCP Permissions

#### For Initial Project Creation

If you're setting up a new project, you need:
- Organization or Folder Admin access (to create projects)
- Billing Account Administrator (to link billing account)
- Owner/Editor on the project (automatically granted as creator)

#### For Team Members Joining an Existing Project

If you're joining an existing project, you need:
- Basic IAM access to the project (View or Editor role)

The bootstrap script will automatically create and assign a custom "developer" role with all necessary permissions.

### Repository Setup

#### Option A: Create a New Repository from Scratch

```bash
# 1. Create a new repository on GitHub
# 2. Clone your empty repository
git clone https://github.com/your-username/your-project-name.git
cd your-project-name

# 3. Download the project files (without Git history)
curl -L https://github.com/fddiferd/fast-api-app/archive/refs/heads/main.zip -o main.zip
unzip main.zip
mv fast-api-app-main/* .
mv fast-api-app-main/.* . 2>/dev/null || true
rmdir fast-api-app-main
rm main.zip

# 4. Commit the initial code
git add .
git commit -m "Initial commit"
git push origin main
```

#### Option B: Fork the Repository

```bash
# 1. Fork the repository on GitHub by visiting:
# https://github.com/fddiferd/fast-api-app/fork

# 2. Clone your forked repository
git clone https://github.com/your-username/fast-api-app.git
cd fast-api-app
```

### Environment Configuration

1. Create your `.env` file from the example template:
   ```bash
   # Copy the example file
   cp .env.example .env
   
   # Edit the .env file with your details
   # Find your billing account ID by running: gcloud billing accounts list
   GCP_BILLING_ACCOUNT_ID=XXXXXX-XXXXXX-XXXXXX  # Your GCP billing account ID
   DEV_SCHEMA_NAME=your-username               # Your unique developer name
   MODE=dev                                    # dev, staging, or prod
   SKIP_TERRAFORM=false                        # Set to true to skip Terraform
   ```

   **Important Note About Billing**: 
   - The billing account ID must be in the correct format (e.g., `01224A-A47992-31AB42`)
   - You must have billing administrator permissions for this account
   - If joining an existing project with billing already configured, set `SKIP_TERRAFORM=true`

2. Update the `config` file if needed (usually only for changing project defaults):
   ```
   # Only modify if you need to change project-level settings
   gcp_project_id: str = 'your-project-name'
   environments: list[str] = ["dev", "staging", "prod"]
   service_name: str = "your-service-name"
   repo_name: str = "your-repo-name"
   region: str = "us-central1"
   ```

### Dependencies Installation

Choose one of the following methods:

**Option 1: Using pip (direct installation):**
```bash
pip install -e .
```

**Option 2: Using Poetry (recommended for development):**
```bash
# Install Poetry if you don't have it
curl -sSL https://install.python-poetry.org | python3 -
# Install dependencies using Poetry
poetry install
```

## Core Workflows

### Initial Verification

Run the verification script to ensure everything is properly set up:

```bash
./setup.sh
```

This checks that all necessary files exist and verifies the application works properly.

### Bootstrapping Your Project

Create a new GCP project with all necessary services enabled:

```bash
./bootstrap
```

This will:
1. Create a GCP project with the naming pattern:
   - Dev: `<project_id>-dev-<dev_schema_name>`
   - Staging/Prod: `<project_id>-<environment>`
2. Enable required GCP APIs
3. Set up Firebase integration
4. Configure Artifact Registry and IAM permissions
5. Set up Cloud Build triggers

### Deploying the Application

Deploy the application to Cloud Run:

```bash
# Standard deployment
./deploy

# With a specific tag
./deploy --tag=v1.0.0
```

This will:
1. Create the Artifact Registry repository if needed
2. Build a Docker image compatible with Cloud Run
3. Push the image to Artifact Registry
4. Deploy the application to Cloud Run

### Accessing Your API

After deployment, use the helper script to get your API URL:

```bash
# Get the base API URL
./get-api-url

# Get URL with health endpoint and make a request
./get-api-url health --curl

# Get URL with CICD test endpoint
./get-api-url cicd-test
```

The API provides these endpoints:
- Health check: `{API_URL}/health`
- CICD test: `{API_URL}/cicd-test`
- Main endpoint: `{API_URL}/`

## CI/CD Pipeline

### Automated Deployments

The CI/CD pipeline is automatically configured during bootstrap and works as follows:

- **Development**: Deploys when any branch except `main` is pushed
- **Staging**: Deploys when changes are pushed to the `main` branch
- **Production**: Deploys when a tag starting with `v` is created (e.g., v1.0.0)

### Testing CI/CD Events

Use the simulation tool to test CI/CD events without actually pushing changes:

```bash
# Test development branch deployment
./simulate dev --branch=feature/my-feature

# Test staging deployment
./simulate main

# Test production deployment
./simulate tag --tag=v1.2.3

# Test PR events
./simulate pr --pr-title="Add new feature"
```

### Pipeline Verification

Verify your CI/CD pipeline configuration:

```bash
# Run just the CI/CD tests
python -m pytest tests/test_cicd.py

# Run all tests including CI/CD tests
./scripts/test/run_tests.sh
```

## Development Guide

### Local Development

1. Install dependencies:
   ```bash
   pip install -e .   # or 'poetry install'
   ```

2. Run the application locally:
   ```bash
   python -m uvicorn app.run:app --reload
   ```

3. Run tests:
   ```bash
   python -m pytest
   ```

### Docker Development

1. Build the Docker image:
   ```bash
   # For local development (native architecture)
   docker build -t fast-api:local -f docker/Dockerfile .
   
   # For Cloud Run compatibility
   docker build --platform linux/amd64 -t fast-api:local -f docker/Dockerfile .
   ```

2. Run the Docker container:
   ```bash
   docker run -p 8000:8000 fast-api:local
   ```

### Git Workflow

**Working with Feature Branches:**
```bash
# Create a new feature branch
git checkout -b feature/new-feature

# Make changes, then commit and push
git add .
git commit -m "Add new feature"
git push origin feature/new-feature

# Merge to main when ready
git checkout main
git pull origin main
git merge feature/new-feature
git push origin main
```

## Features

### Firestore Integration

This project supports both Firestore Native Mode and Datastore Mode:

```bash
# The bootstrap process will:
# 1. Detect existing Firestore databases
# 2. Create a new database in Native Mode if none exists
# 3. Skip database creation when one already exists
```

#### Testing Firestore Integration

Once deployed, test the Firestore integration with:

```bash
# Create a customer
curl -X POST -H "Content-Type: application/json" \
  -d '{"name": "Test Customer", "email": "test@example.com"}' \
  $(./get-api-url)/api/customer

# Retrieve a customer
curl -s $(./get-api-url)/api/customer/[CUSTOMER-ID]

# List all customers
curl -s $(./get-api-url)/api/customers
```

### GitHub Integration

The bootstrap process includes improved GitHub connection detection:

1. Automatically detects when GitHub is already connected to Cloud Build
2. Skips unnecessary GitHub connection prompts when already set up

Add this to your `.env` file to explicitly confirm GitHub is connected:

```
GITHUB_ALREADY_CONNECTED=true
```

## Troubleshooting

### Common Setup Issues

1. **GCP Billing Account Configuration**:
   - Use `gcloud billing accounts list` to see available billing accounts
   - Ensure the billing account ID format is correct and you have admin permissions
   - For existing projects, set `SKIP_TERRAFORM=true` in your `.env`

2. **Terraform Resource Conflicts**:
   - For "resource already exists" errors, you can:
     - Set `SKIP_TERRAFORM=true` in your `.env` file
     - Run deployment directly with `./scripts/cicd/deploy.sh`
     - Manually import existing resources with `terraform import`

3. **Permission Issues**:
   - Run `gcloud auth login` to authenticate
   - Make sure you have the right permissions for the GCP project

4. **Project ID Format Issues**:
   - GCP project IDs must be lowercase alphanumeric with optional hyphens
   - Must be between 6-30 characters (longer IDs are automatically truncated)

### Deployment Issues

1. **Container Startup Problems**:
   - If you see `"The user-provided container failed to start"` error:
     - Ensure the Dockerfile uses port 8000 (matching Cloud Run expectations)
     - Check that your app listens on the port specified by the PORT environment variable
     - Verify your app starts within the timeout period

2. **IAM Policy Binding Failures**:
   - If you see `"Setting IAM policy failed"` error:
     ```bash
     gcloud beta run services add-iam-policy-binding --region=us-central1 \
       --member=allUsers --role=roles/run.invoker SERVICE_NAME
     ```

3. **Permission Issues with Service Accounts**:
   - If you see `"Permission 'iam.serviceaccounts.actAs' denied"` error:
     ```bash
     # Grant the Cloud Run service account permission to act as itself
     gcloud iam service-accounts add-iam-policy-binding \
       SERVICE_ACCOUNT_EMAIL \
       --member="serviceAccount:SERVICE_ACCOUNT_EMAIL" \
       --role="roles/iam.serviceAccountUser"
     
     # Grant the Cloud Build service account permission to use the Cloud Run service account
     gcloud iam service-accounts add-iam-policy-binding \
       SERVICE_ACCOUNT_EMAIL \
       --member="serviceAccount:PROJECT_NUMBER@cloudbuild.gserviceaccount.com" \
       --role="roles/iam.serviceAccountUser"
     ```

4. **Improving Cold Start Times**:
   ```bash
   gcloud run services update SERVICE_NAME --region=us-central1 --cpu-boost --timeout=300s
   ```

### Manual Terraform Operations

**Reset Terraform State:**
```bash
# For Bootstrap Terraform
cd terraform/bootstrap
rm -f terraform.tfstate terraform.tfstate.backup
terraform init
terraform apply

# For CICD Terraform
cd terraform/cicd
rm -f terraform.tfstate terraform.tfstate.backup
terraform init
terraform apply
```

**Import Existing Resources:**
```bash
# Import Artifact Registry
cd terraform/bootstrap
terraform import "google_artifact_registry_repository.api_repo[\"dev\"]" \
  "projects/PROJECT_NAME/locations/REGION/repositories/REPO_NAME"

# Import Cloud Run service
cd terraform/cicd
terraform import google_cloud_run_v2_service.api_service[0] \
  "projects/PROJECT_NAME/locations/REGION/services/SERVICE_NAME"
```

## Reference

### Useful Commands

**Project Management:**
```bash
# Check project status
gcloud projects describe <PROJECT_ID>

# View service logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=<SERVICE_NAME>" --project=<PROJECT_ID>
```

**Deployment & Access:**
```bash
# View Cloud Run service details
gcloud run services describe <SERVICE_NAME> --region=<REGION> --project=<PROJECT_ID>

# Get service URL
gcloud run services describe <SERVICE_NAME> --region=<REGION> --project=<PROJECT_ID> --format="value(status.url)"

# Check service health
curl -s $(./get-api-url health)
```

**CI/CD Management:**
```bash
# List Cloud Build triggers
gcloud builds triggers list --project=<PROJECT_ID>

# View recent Cloud Build history
gcloud builds list --project=<PROJECT_ID>
```

### Compatibility Notes

This project is fully compatible with macOS, Linux, and other Unix-like systems:

- Uses portable shell commands that work across platforms
- Provides correct Docker platform targeting for M1/M2 Macs
- Scripts detect and accommodate different environment configurations