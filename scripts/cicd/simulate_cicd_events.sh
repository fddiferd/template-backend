#!/bin/bash
set -e

echo "===================================================================="
echo "            CI/CD Event Simulation Tool                              "
echo "===================================================================="

# Load environment variables
source .env

# Load config values using a more portable approach for macOS
# Function to extract values from config file (macOS compatible)
extract_config_value() {
    local key=$1
    local value
    value=$(grep "^$key: str = " config | sed -E "s/^$key: str = ['\"](.*)['\"].*$/\1/")
    echo "$value"
}

GCP_PROJECT_ID=$(extract_config_value "gcp_project_id")
SERVICE_NAME=$(extract_config_value "service_name")
REPO_NAME=$(extract_config_value "repo_name")
REGION=$(extract_config_value "region")

# Check if PROJECT_ID from config is available
if [ -z "$GCP_PROJECT_ID" ]; then
  echo "Error: gcp_project_id is not set in config file"
  exit 1
fi

# Use PROJECT_ID from .env if specified, otherwise use from config
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID="$GCP_PROJECT_ID"
fi

# Set project name based on mode
if [ "$MODE" == "dev" ]; then
  if [ -z "$DEV_SCHEMA_NAME" ]; then
    echo "DEV_SCHEMA_NAME not set in .env, required for dev mode"
    exit 1
  fi
  # Convert to lowercase using tr (macOS compatible)
  PROJECT_ID_LOWER=$(echo "$PROJECT_ID" | tr '[:upper:]' '[:lower:]')
  DEV_SCHEMA_LOWER=$(echo "$DEV_SCHEMA_NAME" | tr '[:upper:]' '[:lower:]')
  PROJECT_NAME="${PROJECT_ID_LOWER}-dev-${DEV_SCHEMA_LOWER}"
elif [ "$MODE" == "staging" ]; then
  PROJECT_ID_LOWER=$(echo "$PROJECT_ID" | tr '[:upper:]' '[:lower:]')
  PROJECT_NAME="${PROJECT_ID_LOWER}-staging"
elif [ "$MODE" == "prod" ]; then
  PROJECT_ID_LOWER=$(echo "$PROJECT_ID" | tr '[:upper:]' '[:lower:]')
  PROJECT_NAME="${PROJECT_ID_LOWER}-prod"
else
  echo "Invalid MODE: $MODE. Must be dev, staging, or prod."
  exit 1
fi

# Function to print section headers
function print_section() {
    echo "--------------------------------------------------------------------"
    echo "$1"
    echo "--------------------------------------------------------------------"
}

function print_usage() {
    echo "Usage: $0 <event-type> [options]"
    echo ""
    echo "Event Types:"
    echo "  dev        - Simulate a push to a development branch"
    echo "  main       - Simulate a push to the main branch"
    echo "  tag        - Simulate creating a version tag"
    echo "  pr         - Simulate a pull request"
    echo ""
    echo "Options:"
    echo "  --branch   - Branch name for dev event (default: feature/test)"
    echo "  --tag      - Tag name for tag event (default: v1.0.0-test)"
    echo "  --pr-title - PR title for PR event (default: Test PR)"
    echo ""
    echo "Examples:"
    echo "  $0 dev --branch=feature/auth"
    echo "  $0 main"
    echo "  $0 tag --tag=v2.1.0"
    echo "  $0 pr --pr-title=\"Fix documentation\""
}

# Default values
BRANCH_NAME="feature/test"
TAG_NAME="v1.0.0-test"
PR_TITLE="Test PR"

# Parse arguments
EVENT_TYPE=$1
shift || true

if [ -z "$EVENT_TYPE" ]; then
    print_usage
    exit 1
fi

# Parse options
for arg in "$@"; do
    case $arg in
        --branch=*)
        BRANCH_NAME="${arg#*=}"
        shift
        ;;
        --tag=*)
        TAG_NAME="${arg#*=}"
        shift
        ;;
        --pr-title=*)
        PR_TITLE="${arg#*=}"
        shift
        ;;
        *)
        # Unknown option
        echo "Unknown option: $arg"
        print_usage
        exit 1
        ;;
    esac
done

print_section "CI/CD Event Simulation"
echo "Project: $PROJECT_NAME"
echo "Mode: $MODE"

# Check if gcloud is available
if ! command -v gcloud &> /dev/null; then
    echo "Error: gcloud command not found. Please install Google Cloud SDK."
    exit 1
fi

# Check if git is available
if ! command -v git &> /dev/null; then
    echo "Error: git command not found. Please install git."
    exit 1
fi

# Ensure we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository."
    exit 1
fi

# Simulate CI/CD event based on type
case $EVENT_TYPE in
    dev)
        print_section "Simulating push to development branch: $BRANCH_NAME"
        
        # Check if branch exists, create if not
        if ! git show-ref --verify --quiet refs/heads/$BRANCH_NAME; then
            git branch $BRANCH_NAME
            echo "Created branch $BRANCH_NAME"
        fi
        
        # Look up the dev trigger ID
        echo "Looking for development trigger..."
        TRIGGER_ID=$(gcloud builds triggers list --project=$PROJECT_NAME --filter="description~'dev'" --format="value(id)")
        
        # Simulate the build process by manually triggering Cloud Build
        if [ -n "$TRIGGER_ID" ]; then
            echo "Found trigger ID: $TRIGGER_ID"
            echo "Manually triggering Cloud Build for $BRANCH_NAME..."
            gcloud builds triggers run $TRIGGER_ID --project=$PROJECT_NAME --branch=$BRANCH_NAME --region=$REGION
        else
            echo "Note: No dev trigger found. This may be because triggers are not configured yet."
            echo "To create triggers, run bootstrap with SKIP_TERRAFORM=false in your .env file."
        fi
        
        echo "✅ Development branch event simulated"
        echo "To see build results: https://console.cloud.google.com/cloud-build/builds?project=$PROJECT_NAME"
        ;;
    
    main)
        print_section "Simulating push to main branch"
        
        # Look up the staging trigger ID
        echo "Looking for main branch trigger..."
        TRIGGER_ID=$(gcloud builds triggers list --project=$PROJECT_NAME --filter="description~'staging'" --format="value(id)")
        
        # Simulate the build process by manually triggering Cloud Build
        if [ -n "$TRIGGER_ID" ]; then
            echo "Found trigger ID: $TRIGGER_ID"
            echo "Manually triggering Cloud Build for main branch..."
            gcloud builds triggers run $TRIGGER_ID --project=$PROJECT_NAME --branch=main --region=$REGION
        else
            echo "Note: No main branch trigger found. This may be because triggers are not configured yet."
            echo "To create triggers, run bootstrap with SKIP_TERRAFORM=false in your .env file."
        fi
        
        echo "✅ Main branch event simulated"
        echo "To see build results: https://console.cloud.google.com/cloud-build/builds?project=$PROJECT_NAME"
        ;;
    
    tag)
        print_section "Simulating tag creation: $TAG_NAME"
        
        # Check if tag exists
        if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
            echo "Tag $TAG_NAME already exists. Using existing tag."
        else
            # Create a new tag
            git tag $TAG_NAME
            echo "Created tag $TAG_NAME"
        fi
        
        # Look up the prod trigger ID
        echo "Looking for tag trigger..."
        TRIGGER_ID=$(gcloud builds triggers list --project=$PROJECT_NAME --filter="description~'prod'" --format="value(id)")
        
        # Simulate the build process by manually triggering Cloud Build
        if [ -n "$TRIGGER_ID" ]; then
            echo "Found trigger ID: $TRIGGER_ID"
            echo "Manually triggering Cloud Build for tag $TAG_NAME..."
            gcloud builds triggers run $TRIGGER_ID --project=$PROJECT_NAME --tag=$TAG_NAME --region=$REGION
        else
            echo "Note: No tag trigger found. This may be because triggers are not configured yet."
            echo "To create triggers, run bootstrap with SKIP_TERRAFORM=false in your .env file."
        fi
        
        echo "✅ Tag event simulated"
        echo "To see build results: https://console.cloud.google.com/cloud-build/builds?project=$PROJECT_NAME"
        ;;
    
    pr)
        print_section "Simulating pull request: $PR_TITLE"
        
        echo "This is a simulation only. In a real environment, a PR would be created with title: '$PR_TITLE'"
        echo "In GitHub Actions or other CI systems, this would typically trigger a workflow to:"
        echo "1. Build the application"
        echo "2. Run tests"
        echo "3. Deploy to a preview environment"
        
        # Create a sample branch for this PR if it doesn't exist
        PR_BRANCH="pr/$(date +%s)"
        git branch $PR_BRANCH
        
        echo "Created branch $PR_BRANCH to represent this PR"
        echo "✅ Pull request event simulated (local only)"
        ;;
    
    *)
        echo "Unknown event type: $EVENT_TYPE"
        print_usage
        exit 1
        ;;
esac

echo ""
echo "===================================================================="
echo "CI/CD event simulation complete! This was a simulation only."
echo "Review the output above to see the actual status of the trigger."
echo "====================================================================" 