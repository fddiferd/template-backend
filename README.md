# FastAPI Application with GCP Deployment

This repository contains a FastAPI application with automated infrastructure for deployment to Google Cloud Platform using Cloud Run, Artifact Registry, and Firebase integration.

## Project Structure

- `app/`: FastAPI application code
- `terraform/`: Infrastructure as Code using Terraform
  - `bootstrap/`: Initial GCP project setup
  - `cicd/`: CI/CD and deployment configuration
- `tests/`: Application tests
- Scripts:
  - `bootstrap.sh`: Creates and configures GCP projects
  - `deploy.sh`: Manual deployment script
- Configuration:
  - `config`: Project-level configuration (shared across all developers)
  - `.env`: Developer-specific environment variables

## Configuration

### Project Configuration

The `config` file contains project-level settings that are shared across all developers:

```
# Project configuration (shared across all developers)
gcp_project_id: str = 'fast-api-app'
environments: list[str] = ["dev", "staging", "prod"]
service_name: str = "fast-api"
repo_name: str = "fast-api"
region: str = "us-central1"
# ... other project settings
```

### Developer Environment

The `.env` file contains developer-specific settings:

```
GCP_BILLING_ACCOUNT_ID=your-billing-account-id
DEV_SCHEMA_NAME=your-username
MODE=dev  # dev, staging, or prod
```

## Environment Setup

1. Configure your `.env` file with your developer-specific variables
   
2. Run the bootstrap script to set up the GCP project:
   ```
   ./bootstrap.sh
   ```

   To set up all environments (dev, staging, prod):
   ```
   ./bootstrap.sh all-environments
   ```

## Deployment

The application automatically deploys when code is pushed:
- Push to any branch: Deploys to dev environment
- Push to main branch: Deploys to staging environment
- Create a tag starting with 'v': Deploys to production

For manual deployment:
```
./deploy.sh
```

## Development

1. Install dependencies:
   ```
   pip install poetry
   poetry install
   ```

2. Run the application locally:
   ```
   poetry run uvicorn app.run:app --reload
   ```

3. Run tests:
   ```
   poetry run pytest
   ```

## Infrastructure

The infrastructure is managed with Terraform:

- GCP Projects with environment-specific naming:
  - Dev: `<project_id>-<dev_schema_name>` (unique per developer)
  - Staging: `<project_id>-staging`
  - Prod: `<project_id>-prod`
- Firebase integration
- Artifact Registry for Docker images
- Cloud Run for hosting the API
- Cloud Build for CI/CD
- IAM permissions and service accounts

## CI/CD Pipeline

The CI/CD pipeline is defined in `cloudbuild.yaml` and automatically:

1. Builds a Docker image from the Dockerfile
2. Pushes the image to Artifact Registry
3. Deploys the image to Cloud Run
4. Tags the image as latest

## License

MIT