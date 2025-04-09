# Backend Template - FastAPI Application with GCP Deployment

This repository contains a FastAPI application with automated infrastructure for deployment to Google Cloud Platform using Cloud Run, Artifact Registry, and Firebase integration.

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
    - `terraform.tfvars.example`: Example template for bootstrap variables (the actual `.tfvars` files are gitignored)
  - `cicd/`: CI/CD and deployment configuration
    - `terraform.tfvars.example`: Example template for CICD variables (the actual `.tfvars` files are gitignored)
- `tests/`: Application tests
  - `test_app_exists.py`: Tests for application code integrity
  - `test_infrastructure.py`: Tests for infrastructure configuration
  - `test_cicd.py`: Tests for CI/CD pipeline configuration
- Shortcut Scripts:
  - `bootstrap`: Wrapper script for ./scripts/setup/bootstrap.sh
  - `deploy`: Wrapper script for ./scripts/cicd/deploy.sh
  - `simulate`: Wrapper script for ./scripts/cicd/simulate_cicd_events.sh
- Configuration:
  - `.env`: Developer-specific environment variables
  - `pyproject.toml`: Python project definition and dependencies

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

Create your `.env` file based on the provided `.env.example` template:

```bash
# Copy the example file and customize with your own values
cp .env.example .env
```

The `.env` file contains developer-specific settings:

```
GCP_BILLING_ACCOUNT_ID=000000-000000  # Your GCP billing account ID
DEV_SCHEMA_NAME=your-username                # Your unique developer name
MODE=dev                                     # dev, staging, or prod
SKIP_TERRAFORM=true                          # Skip Terraform deployment (optional)
```

## Initial Setup

### Prerequisites

Before starting, ensure you have the following:

1. Google Cloud SDK installed and configured
   ```
   # Install Google Cloud SDK
   curl https://sdk.cloud.google.com | bash
   # Initialize Google Cloud SDK
   gcloud init
   ```

2. Terraform installed (optional - only if you want to use Terraform)
   ```
   # On macOS with Homebrew
   brew install terraform
   # On Linux
   sudo apt-get install terraform
   ```

3. Python 3.11+ installed
   ```
   # Install Python (if not already installed)
   # macOS
   brew install python@3.11
   # Ubuntu
   sudo apt-get install python3.11
   ```

4. Docker installed (for local testing and builds)

### GCP Permissions

Depending on your role in the project, you'll need different GCP permissions:

#### For Initial Project Creation

If you're setting up a new project, you need:
- Organization or Folder Admin access (to create projects)
- Billing Account Administrator (to link billing account)
- Owner/Editor on the project (automatically granted as creator)

#### For Team Members Joining an Existing Project

If you're joining an existing project, you need:
- Basic IAM access to the project (View or Editor role)

The bootstrap script will automatically create and assign a custom "developer" role with all necessary permissions:
- Artifact Registry management
- Cloud Run service deployment
- Storage object access
- And other permissions needed for development

This eliminates the need to manually assign multiple individual roles.

### Step 1: Set Up Your Repository

You have two options to get started:

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

### Step 2: Configure Your Environment

1. Create your `.env` file from the example template:
   ```bash
   # Copy the example file
   cp .env.example .env
   
   # Edit the .env file with your details
   # Find your billing account ID by running: gcloud billing accounts list
   GCP_BILLING_ACCOUNT_ID=000000-000000  # Your GCP billing account ID (format: XXXXXX-XXXXXX-XXXXXX)
   DEV_SCHEMA_NAME=your-username        # Your unique developer name
   MODE=dev                             # dev, staging, or prod
   SKIP_TERRAFORM=false                 # Set to true to skip Terraform deployment
   ```

   **Important Note About Billing**: 
   - The billing account ID is used to automatically link billing to your GCP projects during bootstrapping
   - The ID must be in the correct format (e.g., `01224A-A47992-31AB42`)
   - You must have billing administrator permissions for this account
   - If joining an existing project that already has billing configured, you can set `SKIP_TERRAFORM=true` to skip this step

2. Update the `config` file if needed (usually only for changing project defaults):
   ```bash
   # Only modify if you need to change project-level settings
   gcp_project_id: str = 'your-project-name'
   ```

### Step 3: Install Dependencies

Install Python dependencies using one of the following methods:

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

## Getting Started

### Step 1: Verify the Library

Run the verification script to ensure everything is properly set up:

```bash
# Using the wrapper script

./setup.sh
```
reference to ```./scripts/test/verify_library.sh```

This will check that all necessary files exist and run tests to verify the application works properly.

### Step 2: Bootstrap Your GCP Project

The bootstrap script creates a new GCP project with all the necessary services enabled:

```bash
# Using the wrapper script

./bootstrap
```
reference to ```./scripts/setup/bootstrap.sh```

This will:
1. Create a GCP project with pattern `<project_id>-dev-<dev_schema_name>` for dev, or `<project_id>-<environment>` for staging/prod
2. Enable required GCP APIs
3. Set up Firebase integration (if Terraform is enabled)
4. Configure Artifact Registry
5. Set up IAM permissions (if Terraform is enabled)
6. Configure Cloud Build triggers (if Terraform is enabled)

### Step 3: Deploy the Application

After bootstrapping, you can deploy the application:

```bash
# Using the wrapper script
./deploy

# With a specific tag
./deploy --tag=v1.0.0
```
reference to ```./scripts/cicd/deploy.sh```

This will:
1. Create the Artifact Registry repository if it doesn't exist
2. Build a Docker image compatible with Cloud Run (linux/amd64)
3. Push the image to Artifact Registry
4. Deploy the application to Cloud Run

## CI/CD Pipeline

The CI/CD pipeline is automatically configured during bootstrap and works as follows:

- **Development**: Deploys when any branch except `main` is pushed
- **Staging**: Deploys when changes are pushed to the `main` branch
- **Production**: Deploys when a tag starting with `v` is created (e.g., v1.0.0)

### Testing CI/CD Events

You can use the included simulation tool to test CI/CD events without actually pushing changes:

```bash
# Using the wrapper script
./simulate dev --branch=feature/my-feature

# Or the full path
./scripts/cicd/simulate_cicd_events.sh dev --branch=feature/my-feature

# Other examples
./simulate main
./simulate tag --tag=v1.2.3
./simulate pr --pr-title="Add new feature"
```

This tool creates the necessary Git objects locally and attempts to trigger the corresponding Cloud Build triggers, giving you feedback on whether the triggers are configured correctly.

### CI/CD Tests

The repository includes tests to verify the CI/CD pipeline configuration:

```bash
# Run just the CI/CD tests
python -m pytest tests/test_cicd.py

# Run all tests including CI/CD tests
./scripts/test/run_tests.sh
```

These tests verify that:
- Cloud Build triggers are properly configured for each environment
- The correct branch patterns are used (development, main, tags)
- Necessary permissions are in place
- Docker build and push steps are configured correctly

## Development

### Local Development

1. Install dependencies using one of the following methods:

   **Using pip:**
   ```bash
   pip install -e .
   ```

   **Using Poetry:**
   ```bash
   poetry install
   ```

2. Run the application locally:

   **With pip installation:**
   ```bash
   python -m uvicorn app.run:app --reload
   ```

   **With Poetry:**
   ```bash
   poetry run uvicorn app.run:app --reload
   ```

3. Run tests:

   **With pip installation:**
   ```bash
   python -m pytest
   ```

   **With Poetry:**
   ```bash
   poetry run pytest
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

## macOS Compatibility

This project is fully compatible with macOS. The scripts use portable shell commands that work across Linux, macOS, and other Unix-like systems:

1. Uses `tr` instead of Bash-specific lowercase syntax for project IDs
2. Uses a portable `sed` command for config file parsing
3. Provides correct Docker platform targeting for M1/M2 Macs

## Troubleshooting

### Common Issues

1. **GCP Billing Account Configuration**:
   - Billing account format must be correct (e.g., `01224A-A47992-31AB42`)
   - Run `gcloud billing accounts list` to see available billing accounts
   - If you get a 403 error during Terraform deployment, check that:
     - The billing account ID format is correct
     - You have billing administrator permissions
     - Billing is properly enabled on the project
   - If working with an existing project, you may want to set `SKIP_TERRAFORM=true` in your `.env`

2. **Terraform Resource Conflicts**:
   - If you see `Error: Error creating Repository: googleapi: Error 409: the repository already exists`
   - This happens when Terraform tries to create resources that already exist
   - The bootstrap script now detects existing Artifact Registry repositories and adjusts the Terraform code
   - If you encounter other similar errors, you can:
     - Set `SKIP_TERRAFORM=true` in your `.env` file to skip Terraform entirely
     - Run deployment directly with `./scripts/cicd/deploy.sh`
     - For more complex cases, you might need to manually import existing resources with `terraform import`

3. **CICD Terraform Errors**:
   - If you see errors with the CICD Terraform configuration referencing other projects (like "wedge-golf-dev")
   - This happens when the Terraform state has references to resources in other projects
   - To fix this:
     1. Delete the Terraform state: `cd terraform/cicd && rm -f terraform.tfstate terraform.tfstate.backup`
     2. Re-run the bootstrap with `./scripts/setup/bootstrap.sh`
     3. If you still encounter errors, run the deployment directly with `./scripts/cicd/deploy.sh`
   - The deployment script will work even if the CICD Terraform has errors

4. **Permission Issues**:
   - Run `gcloud auth login` to authenticate
   - Make sure you have the right permissions for the GCP project
   - Review the GCP Permissions section to ensure you have the necessary roles

5. **Failed Tests**:
   - Run `./scripts/test/run_tests.sh` to automatically install missing dependencies

6. **CI/CD Triggers Not Working**:
   - Verify the triggers are properly configured in GCP console
   - Check that the branch patterns match your Git workflow
   - Use `./simulate` to test trigger configuration

7. **Docker Build Issues on M1/M2 Macs**:
   - Make sure to use `--platform linux/amd64` when building for Cloud Run
   - Docker Desktop must be running with Rosetta 2 emulation enabled

8. **Project ID Format Issues**:
   - GCP project IDs must be lowercase alphanumeric with optional hyphens
   - Underscores are not allowed in project IDs

9. **Active Project Mismatch**:
   - The scripts will detect if your active gcloud configuration uses a different project
   - You'll be given the option to switch your configuration to the target project
   - If you choose not to switch, all script commands will still work correctly (they use explicit project flags)
   - But be careful when running manual gcloud commands as they'll use your active configuration

### Manual Terraform Operations

For most users, you won't need to run Terraform commands directly as the bootstrap and deploy scripts handle this for you. However, in certain troubleshooting scenarios, you might need to:

**Reset Terraform State (when it references wrong projects):**
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

**Import Existing Resources to Terraform State:**
```bash
# Example for importing an existing Artifact Registry
cd terraform/bootstrap
terraform import "google_artifact_registry_repository.api_repo[\"dev\"]" \
  "projects/PROJECT_NAME/locations/REGION/repositories/REPO_NAME"

# Example for importing an existing Cloud Run service
cd terraform/cicd
terraform import google_cloud_run_v2_service.api_service \
  "projects/PROJECT_NAME/locations/REGION/services/SERVICE_NAME"
```

### Git Workflow

**Pull Changes Into Main:**
```bash
# First checkout the main branch
git checkout main

# Pull the latest changes from the remote main
git pull origin main

# To merge a feature branch into main:
git merge feature/your-branch-name

# Push the changes to remote main
git push origin main
```

**Creating and Using Feature Branches:**
```bash
# Create a new feature branch
git checkout -b feature/new-feature

# Make your changes, then commit
git add .
git commit -m "Add new feature"

# Push to remote
git push origin feature/new-feature

# When ready, merge to main as shown above
```

### Useful Commands

- Check project status:
  ```
  gcloud projects describe <PROJECT_ID>
  ```

- View deployed service:
  ```
  gcloud run services describe <SERVICE_NAME> --region=<REGION> --project=<PROJECT_ID>
  ```

- View service logs:
  ```
  gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=<SERVICE_NAME>" --project=<PROJECT_ID>
  ```

- List Cloud Build triggers:
  ```
  gcloud builds triggers list --project=<PROJECT_ID>
  ```

- View recent Cloud Build history:
  ```
  gcloud builds list --project=<PROJECT_ID>
  ```

- View Artifact Registry repositories:
  ```
  gcloud artifacts repositories list --project=<PROJECT_ID> --location=<REGION>
  ```

## License

MIT

# Firestore Configuration

This project now supports both Firestore Native Mode and Datastore Mode with improved configuration and detection:

```bash
# The bootstrap process will automatically:
# 1. Detect existing Firestore databases
# 2. Create a new database in Native Mode if none exists
# 3. Skip database creation when one already exists
```

### Firestore Native Mode Support

By default, the project now sets up Firestore in **Native Mode**, which enables:

- Document-oriented database structure
- Real-time updates
- Full Firebase SDK compatibility 
- Better support for complex data modeling

### Testing Firestore Integration

Once deployed, you can test the Firestore integration with the following commands:

```bash
# Create a customer
curl -X POST -H "Content-Type: application/json" \
  -d '{"name": "Test Customer", "email": "test@example.com"}' \
  https://[YOUR-SERVICE-URL]/api/customer

# Retrieve a customer
curl -s https://[YOUR-SERVICE-URL]/api/customer/[CUSTOMER-ID]

# List all customers
curl -s https://[YOUR-SERVICE-URL]/api/customers

# Update a customer
curl -X PUT -H "Content-Type: application/json" \
  -d '{"name": "Updated Customer", "phone": "555-1234"}' \
  https://[YOUR-SERVICE-URL]/api/customer/[CUSTOMER-ID]
```

## GitHub Integration

### Improved GitHub Connection Detection

The bootstrap process now has improved GitHub connection detection:

1. Automatically detects when GitHub is already connected to Cloud Build
2. Skips unnecessary GitHub connection prompts when already set up
3. Provides a flag to explicitly confirm GitHub connection status

Add the following to your `.env` file to explicitly confirm GitHub is connected:

```
# Add this when your GitHub is already connected to Cloud Build
GITHUB_ALREADY_CONNECTED=true
```

### Handling Existing Resources

The deployment process has been enhanced to handle existing resources:

1. Detects when resources already exist to prevent recreation errors
2. Properly manages Terraform state for existing Cloud Run services
3. Allows deployment to continue even when GitHub trigger creation fails
4. Implements proper error handling to prevent stopping the deployment process

## Troubleshooting

### GitHub Connection Issues

If you encounter GitHub connection issues:

1. Check if your GitHub repository is properly connected in the GCP console:
   - Go to: https://console.cloud.google.com/cloud-build/triggers
   - Verify that GitHub is listed as a connected repository

2. If GitHub is connected but the bootstrap process doesn't detect it:
   - Add `GITHUB_ALREADY_CONNECTED=true` to your `.env` file
   - This will skip GitHub connection detection and proceed with deployment

3. If you need to manually connect GitHub:
   - Go to: https://console.cloud.google.com/cloud-build/triggers/connect
   - Select your GitHub repository
   - Install the Cloud Build GitHub app if needed