# Wedge Golf Backend

This repository contains the backend service for Wedge Golf, built with FastAPI and deployed on Google Cloud Run.

## Project Structure

```
.
├── app/                    # Application source code
├── terraform/             # Infrastructure as Code
│   ├── bootstrap/        # Initial project setup
│   └── cicd/            # CI/CD and service deployment
├── cloudbuilds/          # Cloud Build configurations
├── service_accounts/     # Service account credentials
└── Dockerfile           # Container configuration
```

## Prerequisites

- Python 3.11+
- Poetry for dependency management
- Google Cloud SDK
- Terraform 1.5+
- Access to the Google Cloud project(s)

## Local Development

1. Install dependencies:
   ```bash
   poetry install
   ```

2. Set up environment variables:
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

3. Run the development server:
   ```bash
   poetry run uvicorn src.app:app --reload
   ```

## Infrastructure Setup

The infrastructure is managed using Terraform and is split into two stages:

### 1. Bootstrap (One-time setup)

The bootstrap configuration in `terraform/bootstrap` sets up:
- Firebase project configuration
- Required Google Cloud APIs

To apply for each environment:
```bash
cd terraform/bootstrap
terraform init
terraform apply -var="environment=dev"    # For development
terraform apply -var="environment=staging" # For staging
terraform apply -var="environment=prod"   # For production
```

### 2. CI/CD and Service Deployment

The CICD configuration in `terraform/cicd` manages:
- Cloud Run service
- Artifact Registry repository
- Service accounts and IAM permissions
- Public access configuration

To apply for each environment:
```bash
cd terraform/cicd
terraform init
terraform apply -var="environment=dev" -var-file="terraform.tfvars" # For development
terraform apply -var="environment=staging" -var-file="terraform.tfvars" # For staging
terraform apply -var="environment=prod" -var-file="terraform.tfvars"   # For production
```

## Deployment

### Prerequisites
- Docker Desktop installed and running
- Google Cloud SDK installed and configured
- Appropriate IAM permissions (managed through Terraform)
- For ARM-based machines (M1/M2 Mac), ensure Docker Desktop is configured for multi-platform builds
- Must be run from the project root directory where the Dockerfile is located
- Billing must be enabled for the target GCP project
- Artifact Registry repository must be created in the target project

### Manual Deployment

1. Build and push the Docker image for the desired environment:
   ```bash
   # Navigate to the project root directory
   cd /path/to/wedge-backend-production-ready

   # For ARM-based machines (M1/M2 Mac)
   docker buildx build --platform linux/amd64 -t gcr.io/wedge-golf-dev/wedge-api:latest .
   docker push gcr.io/wedge-golf-dev/wedge-api:latest

   # For x86 machines
   docker build -t gcr.io/wedge-golf-dev/wedge-api:latest .
   docker push gcr.io/wedge-golf-dev/wedge-api:latest

   # For staging (requires billing to be enabled)
   docker buildx build --platform linux/amd64 -t gcr.io/wedge-golf-staging/wedge-api:latest .
   docker push gcr.io/wedge-golf-staging/wedge-api:latest

   # For production (requires billing to be enabled)
   docker buildx build --platform linux/amd64 -t gcr.io/wedge-golf-prod/wedge-api:latest .
   docker push gcr.io/wedge-golf-prod/wedge-api:latest
   ```

2. Deploy to Cloud Run for the desired environment:
   ```bash
   # For development
   gcloud run deploy wedge-api \
     --image gcr.io/wedge-golf-dev/wedge-api:latest \
     --platform managed \
     --region us-central1 \
     --project wedge-golf-dev

   # For staging (requires billing to be enabled)
   gcloud run deploy wedge-api \
     --image gcr.io/wedge-golf-staging/wedge-api:latest \
     --platform managed \
     --region us-central1 \
     --project wedge-golf-staging

   # For production (requires billing to be enabled)
   gcloud run deploy wedge-api \
     --image gcr.io/wedge-golf-prod/wedge-api:latest \
     --platform managed \
     --region us-central1 \
     --project wedge-golf-prod
   ```

### Required IAM Permissions
The following IAM roles are required for building and pushing Docker images:
- `roles/artifactregistry.writer` - For pushing Docker images
- `roles/storage.admin` - For storage access
- `roles/logging.logWriter` - For writing build logs

These permissions are managed through Terraform in `terraform/cicd/main.tf`.

### Troubleshooting

1. **Build Failures**
   - Check Cloud Build logs
   - Verify Dockerfile configuration
   - Ensure all required files are included in the build context
   - For ARM-based machines, verify platform compatibility using `docker inspect gcr.io/wedge-golf-dev/wedge-api:latest | grep Architecture`

2. **Deployment Failures**
   - Check service account permissions
   - Verify environment variables are set correctly
   - Check Cloud Run revision logs
   - Ensure Docker image is built for the correct platform (linux/amd64)
   - Verify billing is enabled for the target project
   - Ensure Artifact Registry repository exists in the target project

3. **Runtime Issues**
   - Check application logs in Cloud Logging
   - Verify Firebase credentials are accessible
   - Check resource utilization metrics

## Service Configuration

Each environment's Cloud Run service is configured with:
- Memory: 512Mi
- CPU: 1000m (1 vCPU)
- Concurrency: 80 requests per instance
- Auto-scaling: 0-3 instances
- Startup probe: TCP check on port 8000
- Environment variables:
  - `ENVIRONMENT`: dev/staging/prod
  - `FIREBASE_CRED_PATH`: service_accounts/firebase-{env}.json
  - `HOST`: 0.0.0.0

## Service Accounts

Each environment has its own service account:
1. Cloud Run Service Account (`cloudrun-{env}-sa@wedge-golf-{env}.iam.gserviceaccount.com`)
   - Used by the application for accessing Google Cloud services
   - Has permissions for Firebase, Cloud Storage, and Firestore

2. Cloud Build Service Account (managed by Google Cloud)
   - Used for building and deploying the application
   - Has permissions to deploy to Cloud Run and access Artifact Registry

## Monitoring and Logs

- Cloud Run logs: Available in Google Cloud Console for each environment
- Application logs: Structured JSON logs sent to Cloud Logging
- Metrics: Available in Cloud Monitoring

## Security

- HTTPS enforced by default
- Public endpoint with authentication handled by Firebase Auth
- Secrets managed through environment variables and service account credentials
- IAM permissions follow the principle of least privilege

## Troubleshooting

1. **Build Failures**
   - Check Cloud Build logs
   - Verify Dockerfile configuration
   - Ensure all required files are included in the build context

2. **Deployment Failures**
   - Check service account permissions
   - Verify environment variables are set correctly
   - Check Cloud Run revision logs

3. **Runtime Issues**
   - Check application logs in Cloud Logging
   - Verify Firebase credentials are accessible
   - Check resource utilization metrics

## Contributing

1. Create a new branch from the appropriate environment branch
2. Make your changes
3. Submit a pull request to the target environment branch
4. After review and approval, changes will be merged and automatically deployed

## License

Proprietary - All rights reserved