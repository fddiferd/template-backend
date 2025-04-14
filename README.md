# Wedge Golf CICD Project

A comprehensive Cloud Run application with multi-environment CI/CD pipelines for the Wedge Golf project.

## Project Structure

```
.
├── .github/workflows      # GitHub Actions workflow files for CI/CD
├── backend/               # Backend Python FastAPI application
│   ├── app/               # Application code
│   │   ├── api/           # API endpoints
│   │   └── main.py        # Main application entry point
│   ├── Dockerfile         # Docker configuration for backend
│   └── pyproject.toml     # Python dependencies and project metadata
├── frontend/              # Next.js frontend application
│   ├── src/               # Source code
│   │   └── app/           # Next.js app directory
│   ├── public/            # Static assets
│   └── Dockerfile         # Docker configuration for frontend
├── terraform/             # Infrastructure as Code with Terraform
│   ├── main.tf            # Main Terraform configuration
│   ├── variables.tf       # Variable definitions
│   └── outputs.tf         # Output definitions
├── config.yaml            # Project configuration
├── .env.example           # Example environment variables
├── bootstrap.sh           # Infrastructure bootstrap script
└── deploy.sh              # Deployment script
```

## Getting Started

### Prerequisites

- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)
- [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
- [Git](https://git-scm.com/downloads)
- [Node.js](https://nodejs.org/) (for frontend development)
- [Python 3.11+](https://www.python.org/downloads/) (for backend development)

### Initial Setup

1. Clone this repository:
   ```
   git clone <repository-url>
   cd wedge-golf-cicd
   ```

2. Configure your project:
   - Edit `config.yaml` with your project details
   - Copy the environment variables template:
     ```
     cp .env.example .env
     ```
   - Edit the `.env` file and fill in your developer-specific settings, including your billing account ID

3. Set up Google Cloud SDK:
   ```
   gcloud auth login
   gcloud auth application-default login
   ```

### Project Environments

The project supports three environments:
- `dev`: Individual developer environments (project-id-dev-username)
- `staging`: Shared staging environment (project-id-staging)
- `prod`: Production environment (project-id-prod)

## Infrastructure Management

### Bootstrapping Infrastructure

You can bootstrap one or multiple environments:

```bash
# Bootstrap all environments 
./bootstrap.sh --all --yes

# Bootstrap specific environments
./bootstrap.sh --dev
./bootstrap.sh --prod --staging

# Force recreation of existing projects
./bootstrap.sh --dev --force-new

# Specify a custom developer name
./bootstrap.sh --dev --developer johndoe
```

The bootstrap script will:
1. Check if the project already exists
2. Create or reconfigure the infrastructure based on your selection
3. Generate a service account key for GitHub Actions
4. Provide instructions for setting up GitHub secrets

### GitHub Secrets Setup

After bootstrapping, you'll need to set up GitHub secrets for CI/CD:

1. Add the secrets as described in the bootstrap output
2. Remove the service account key file for security reasons

## Firebase Integration

This project uses Firebase for database storage and authentication. The Firebase resources are automatically set up during the main bootstrap process.

### Firebase Setup

Firebase resources are created during the bootstrap process via `bootstrap.sh`:
- Firebase project connection (linking GCP project to Firebase)
- Firestore database in us-central region
- Firebase Admin SDK service account with appropriate permissions
- Service account keys stored securely in the `secrets/` directory
- Secret Manager integration for accessing credentials

You don't need to run any separate scripts for Firebase setup - it's all integrated into the main bootstrap process.

### Firebase Credentials

Firebase service account credentials are:
1. Generated during bootstrap for each environment as `secrets/firebase-admin-key-{env}.json` files
2. Stored in the `secrets/` directory (which is excluded from git)
3. Uploaded to Secret Manager for secure access by deployed services
4. Automatically used by the backend service based on the current environment

The backend service automatically selects the appropriate credential file based on the `ENVIRONMENT` environment variable. For example:
- `ENVIRONMENT=dev` uses `secrets/firebase-admin-key-dev.json`
- `ENVIRONMENT=staging` uses `secrets/firebase-admin-key-staging.json`
- `ENVIRONMENT=prod` uses `secrets/firebase-admin-key-prod.json`

### CI/CD Integration

The GitHub Actions workflows are configured to:
1. Deploy to the appropriate environment based on branch/PR events
2. Mount the correct Firebase credentials for each environment
3. Set the proper environment variables for backend and frontend

When code is:
- Pushed to a non-main branch → Deploys to dev
- Pushed to main → Deploys to staging
- Merged via PR to main → Deploys to production

### Troubleshooting Firebase

If you encounter issues with Firebase:
1. Ensure the bootstrap script has been run: `./bootstrap.sh --all`
2. Verify Firebase services are enabled: `gcloud services list --project=YOUR_PROJECT_ID | grep firebase`
3. Check if Firestore database exists: `gcloud firestore databases list --project=YOUR_PROJECT_ID`
4. Ensure the proper credentials file exists: `ls -la secrets/firebase-admin-key-*.json`
5. Check Secret Manager for uploaded credentials: `gcloud secrets versions list firebase-credentials --project=YOUR_PROJECT_ID`

## Deployment

Deploy to any environment using the deploy script:

```bash
# Deploy everything to development environment
./deploy.sh --all --dev

# Deploy only backend to staging
./deploy.sh --backend --staging

# Deploy only frontend to production
./deploy.sh --frontend --prod

# Skip confirmation prompts
./deploy.sh --all --dev --yes

# Deploy both backend and frontend to all environments (dev, staging, prod)
./deploy.sh --all --all_envs --yes
```

### Deployment URLs Management

When you deploy your applications, the script automatically saves the service URLs to JSON files:

- `urls/urls.dev.json`: URLs for development environment
- `urls/urls.staging.json`: URLs for staging environment
- `urls/urls.prod.json`: URLs for production environment
- `urls/urls.local.json`: A copy of the development URLs intended for local use

These files contain the backend and frontend Cloud Run URLs for accessing each environment:

```json
{
  "environment": "dev",
  "projectId": "test-wedge-golf-dev-username",
  "backendUrl": "https://backend-api-abc123.a.run.app",
  "frontendUrl": "https://frontend-web-abc123.a.run.app"
}
```

All URL files are gitignored to avoid conflicts between developers. For team-wide access:

- Staging and production URLs should be recorded in your documentation or shared by other means
- Development URLs are personal to each developer (different for each person)
- For local development, reference your local `urls/urls.local.json` file
- Consider adding URL fetching functions in your CI pipeline for application configuration

## CI/CD Pipelines

The project includes GitHub Actions workflows for automated deployment:

- **Development**: Any push to a branch other than main/master automatically deploys to the developer's personal development environment.
- **Staging**: Any push to the main/master branch automatically deploys to the staging environment.
- **Production**: When a pull request to main/master is merged, it triggers a deployment to production.

### GitHub Secrets Configuration

Set up the following secrets in your GitHub repository:

- `GCP_SA_KEY`: The service account key generated during bootstrap
- `DEV_PROJECT_ID`: Base project ID for development
- `STAGING_PROJECT_ID`: Project ID for staging
- `PROD_PROJECT_ID`: Project ID for production

## Local Development

The application consists of two main components - a FastAPI backend and a Next.js frontend. Both can be run locally for development.

### Setting Up Local Environment

1. Create a development `.env` file:
   ```bash
   cp .env.example .env
   ```

2. Set up Firebase emulators (optional):
   ```bash
   firebase emulators:start
   ```

### Backend

Run the backend locally with these steps:

```bash
# Navigate to backend directory
cd backend

# Create and activate a Python virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies from pyproject.toml
pip install -e .

# Run the application
uvicorn app.main:app --reload --host 0.0.0.0 --port 8080
```

After starting, the backend API will be available at http://localhost:8080

### Frontend

Run the frontend locally with these steps:

```bash
# Navigate to frontend directory
cd frontend

# Install dependencies
npm install

# Create local environment file
cp .env.example .env.local
# Edit .env.local to set NEXT_PUBLIC_BACKEND_URL=http://localhost:8080

# Run the development server
npm run dev
```

After starting, the frontend will be available at http://localhost:3000

### Testing Local Setup

1. Start both the backend and frontend in separate terminal windows
2. Navigate to http://localhost:3000 in your browser
3. Click the "Check Backend Health" button to verify the connection
4. You should see a successful response with system information from the backend

### Using URLs from Deployed Environments

If you want to use URLs from deployed environments:

```bash
# Load backend URL from your dev deployment
export NEXT_PUBLIC_BACKEND_URL=$(cat urls/urls.dev.json | jq -r '.backendUrl')
# On Windows PowerShell:
# $env:NEXT_PUBLIC_BACKEND_URL = (Get-Content urls/urls.dev.json | ConvertFrom-Json).backendUrl
```

## Authentication

The application uses Google Cloud's Application Default Credentials for authentication:

1. For local development, credentials are provided by `gcloud auth application-default login`
2. In Cloud Run, credentials are automatically provided by the service account
3. For GitHub Actions, credentials are provided via the GCP_SA_KEY secret

## License

This project is licensed under the MIT License - see the LICENSE file for details. 