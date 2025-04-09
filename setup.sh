#!/bin/bash
set -e

echo "===================================================================="
echo "            FastAPI Application Setup Helper                         "
echo "===================================================================="

#==========================================================================
# SECTION 1: INITIAL SETUP
#==========================================================================
echo
echo "INITIAL SETUP"
echo "------------"

# Check if .env file exists
if [ ! -f ".env" ]; then
  echo "Creating sample .env file..."
  cat > .env << EOF
# Set your GCP billing account ID
GCP_BILLING_ACCOUNT_ID=your-billing-account-id

# Your unique developer identifier (used for dev environments)
DEV_SCHEMA_NAME=your-username

# Set the environment (dev, staging, or prod)
MODE=dev
EOF
  echo "✅ Created .env file. Please edit with your specific settings."
else
  echo "✅ .env file already exists."
fi

# Check for required tools
echo "Checking for required tools..."
command -v git >/dev/null 2>&1 || { echo "❌ Git is required but not installed. Please install Git first."; }
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed. Please install Docker first."; }
command -v gcloud >/dev/null 2>&1 || { echo "❌ Google Cloud SDK is required but not installed. Please install it first."; }
command -v terraform >/dev/null 2>&1 || { echo "❌ Terraform is required but not installed. Please install Terraform first."; }

# Check GCP authentication
echo "Checking GCP authentication..."
if gcloud auth list --filter=status:ACTIVE --format="value(account)" >/dev/null 2>&1; then
  echo "✅ You are authenticated with Google Cloud."
else
  echo "❌ Not authenticated with Google Cloud. Please run 'gcloud auth login'."
fi

#==========================================================================
# SECTION 2: DEPENDENCY SETUP
#==========================================================================
echo
echo "DEPENDENCY SETUP"
echo "---------------"

# Determine Python executable
PYTHON_CMD=""
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
    echo "✅ Found Python 3: $(python3 --version 2>&1)"
elif command -v python &> /dev/null; then
    PYTHON_CMD="python"
    echo "✅ Found Python: $(python --version 2>&1)"
else
    echo "❌ Python not found. Please install Python 3.11 or later."
fi

# Check for Poetry or pip
if command -v poetry &> /dev/null; then
    echo "✅ Poetry is installed. You can use 'poetry install' to install dependencies."
    echo "   Run: poetry install"
else
    echo "ℹ️ Poetry not found. You can install dependencies with pip instead."
    echo "   Run: pip install -e ."
    echo "   Or install Poetry with: curl -sSL https://install.python-poetry.org | python3 -"
fi

echo
echo "Would you like to install the dependencies now? (y/n)"
read -r install_deps
if [[ "$install_deps" =~ ^[Yy]$ ]]; then
    if command -v poetry &> /dev/null; then
        echo "Installing dependencies with Poetry..."
        poetry install
    else
        if [ -n "$PYTHON_CMD" ]; then
            echo "Installing dependencies with pip..."
            $PYTHON_CMD -m pip install -e .
        else
            echo "❌ Cannot install dependencies without Python."
        fi
    fi
fi

#==========================================================================
# SECTION 3: BOOTSTRAP AND DEPLOYMENT
#==========================================================================
echo
echo "BOOTSTRAP AND DEPLOYMENT INSTRUCTIONS"
echo "----------------------------------"
echo "Now you can bootstrap your GCP environment and deploy your application:"
echo

echo "1. Bootstrap your GCP project:"
echo "   ./scripts/setup/bootstrap.sh"
echo 
echo "2. Deploy your application:"
echo "   ./scripts/cicd/deploy.sh"
echo

#==========================================================================
# SECTION 4: TESTING AND VERIFICATION
#==========================================================================
echo
echo "TESTING AND VERIFICATION"
echo "------------------------"
echo "To verify your setup and test the CI/CD pipeline:"
echo

echo "1. Run tests:"
echo "   ./scripts/test/run_tests.sh"
echo
echo "2. Simulate CI/CD events:"
echo "   ./scripts/cicd/simulate_cicd_events.sh [dev|main|tag]"
echo
echo "3. Verify entire project setup:"
echo "   ./scripts/test/verify_library.sh"
echo

echo "For more details, please see the README.md file."
echo "====================================================================" 

# Offer to take the next step
echo "Would you like to proceed with bootstrapping your GCP project now? (y/n)"
read -r bootstrap_now
if [[ "$bootstrap_now" =~ ^[Yy]$ ]]; then
    ./scripts/setup/bootstrap.sh
fi 