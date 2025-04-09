# FastAPI Application with GCP Deployment

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
  - `cicd/`: CI/CD and deployment configuration
- `tests/`: Application tests
  - `test_app_exists.py`: Tests for application code integrity
  - `test_infrastructure.py`: Tests for infrastructure configuration
  - `test_cicd.py`: Tests for CI/CD pipeline configuration
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

The `.env` file contains developer-specific settings:

```
GCP_BILLING_ACCOUNT_ID=your-billing-account-id
DEV_SCHEMA_NAME=your-username
MODE=dev  # dev, staging, or prod
```

## Getting Started

### Prerequisites

Before starting, ensure you have the following:

1. Google Cloud SDK installed and configured
   ```
   # Install Google Cloud SDK
   curl https://sdk.cloud.google.com | bash
   # Initialize Google Cloud SDK
   gcloud init
   ```

2. Terraform installed
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

### Step 1: Clone the Repository

```bash
git clone https://github.com/yourusername/fast-api-app.git
cd fast-api-app
```

### Step 2: Configure Your Environment

1. Set up your `.env` file with your specific settings:
   ```bash
   # Edit the .env file with your details
   GCP_BILLING_ACCOUNT_ID=000000-000000-000000  # Your GCP billing account ID
   DEV_SCHEMA_NAME=your-username                # Your unique developer name
   MODE=dev                                     # dev, staging, or prod
   ```

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

### Step 4: Verify the Library

Run the verification script to ensure everything is properly set up:

```bash
./scripts/test/verify_library.sh
```

This will check that all necessary files exist and run tests to verify the application works properly.

### Step 5: Bootstrap Your GCP Project

The bootstrap script creates a new GCP project with all the necessary services enabled:

```bash
# Bootstrap the environment specified in your .env file (MODE=dev|staging|prod)

./scripts/setup/bootstrap.sh
```

This will:
1. Create a GCP project with pattern `<project_id>-DEV_<dev_schema_name>` for dev, or `<project_id>-<environment>` for staging/prod
2. Enable required GCP APIs
3. Set up Firebase integration
4. Configure Artifact Registry
5. Set up IAM permissions
6. Configure Cloud Build triggers

### Step 6: Deploy the Application

After bootstrapping, you can deploy the application manually:

```bash
./scripts/cicd/deploy.sh
```

This will:
1. Build a Docker image
2. Push the image to Artifact Registry
3. Deploy the application to Cloud Run

## CI/CD Pipeline

The CI/CD pipeline is automatically configured during bootstrap and works as follows:

- **Development**: Deploys when any branch except `main` is pushed
- **Staging**: Deploys when changes are pushed to the `main` branch
- **Production**: Deploys when a tag starting with `v` is created (e.g., v1.0.0)

### Testing CI/CD Events

You can use the included simulation tool to test CI/CD events without actually pushing changes:

```bash
# Simulate a push to a development branch
./scripts/cicd/simulate_cicd_events.sh dev --branch=feature/my-feature

# Simulate a push to the main branch
./scripts/cicd/simulate_cicd_events.sh main

# Simulate creating a version tag
./scripts/cicd/simulate_cicd_events.sh tag --tag=v1.2.3

# Simulate a pull request
./scripts/cicd/simulate_cicd_events.sh pr --pr-title="Add new feature"
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
   docker build -t fast-api:local -f docker/Dockerfile .
   ```

2. Run the Docker container:
   ```bash
   docker run -p 8000:8000 fast-api:local
   ```

## Troubleshooting

### Common Issues

1. **Missing GCP Billing Account ID**:
   - Ensure your billing account ID is correct in `.env`
   - Verify you have billing admin permissions

2. **Permission Issues**:
   - Run `gcloud auth login` to authenticate
   - Make sure you have the right permissions for the GCP project

3. **Failed Tests**:
   - Run `./scripts/test/run_tests.sh` to automatically install missing dependencies

4. **CI/CD Triggers Not Working**:
   - Verify the triggers are properly configured in GCP console
   - Check that the branch patterns match your Git workflow
   - Use `./scripts/cicd/simulate_cicd_events.sh` to test trigger configuration

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

## License

MIT