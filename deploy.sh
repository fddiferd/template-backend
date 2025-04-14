#!/bin/bash
set -e

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="dev"
COMPONENTS="all"
DEVELOPER_NAME=$(whoami)
SKIP_CONFIRM=false
ALL_ENVS=false

# Load .env file if it exists
if [ -f ".env" ]; then
  source .env
  if [ -n "$DEV_USER_NAME" ]; then
    DEVELOPER_NAME="$DEV_USER_NAME"
  fi
fi

function print_usage() {
  echo "Usage: $0 [--all|--backend|--frontend] [--prod|--staging|--dev|--all_envs] [options]"
  echo "  Component options:"
  echo "    --all                 Deploy both backend and frontend (default)"
  echo "    --backend             Deploy only the backend"
  echo "    --frontend            Deploy only the frontend"
  echo ""
  echo "  Environment options:"
  echo "    --prod                Deploy to production environment"
  echo "    --staging             Deploy to staging environment"
  echo "    --dev                 Deploy to development environment (default)"
  echo "    --all_envs            Deploy to all environments (dev, staging, prod)"
  echo ""
  echo "  Other options:"
  echo "    --developer           Developer name for dev environment (default: from .env or current user)"
  echo "    --yes                 Skip confirmation prompts"
  echo "    --help                Show this help message"
}

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --all)
      COMPONENTS="all"
      shift
      ;;
    --backend)
      COMPONENTS="backend"
      shift
      ;;
    --frontend)
      COMPONENTS="frontend"
      shift
      ;;
    --prod)
      ENVIRONMENT="prod"
      shift
      ;;
    --staging)
      ENVIRONMENT="staging"
      shift
      ;;
    --dev)
      ENVIRONMENT="dev"
      shift
      ;;
    --all_envs)
      ALL_ENVS=true
      shift
      ;;
    --developer)
      DEVELOPER_NAME="$2"
      shift
      shift
      ;;
    --yes)
      SKIP_CONFIRM=true
      shift
      ;;
    --help)
      print_usage
      exit 0
      ;;
    *)
      echo -e "${RED}Error: Unknown option $1${NC}"
      print_usage
      exit 1
      ;;
  esac
done

# Set environment short name
if [ "$ENVIRONMENT" == "prod" ]; then
  ENV_SHORT="prod"
elif [ "$ENVIRONMENT" == "staging" ]; then
  ENV_SHORT="staging"
else
  ENV_SHORT="dev"
fi

# Load configuration
if [ ! -f "config.yaml" ]; then
  echo -e "${RED}Error: config.yaml file not found!${NC}"
  exit 1
fi

# Set the project ID based on environment
PROJECT_NAME=$(grep "id:" config.yaml | head -n1 | sed 's/.*id: //' | sed 's/"//g')
if [ "$ENVIRONMENT" == "dev" ]; then
  PROJECT_ID="${PROJECT_NAME}-${ENVIRONMENT}-${DEVELOPER_NAME}"
else
  PROJECT_ID="${PROJECT_NAME}-${ENVIRONMENT}"
fi

# Check if the project exists
echo -e "${BLUE}Checking if project $PROJECT_ID exists...${NC}"
project_exists=$(gcloud projects list --format="value(projectId)" --filter="projectId=$PROJECT_ID" 2>/dev/null || echo "")

if [ -z "$project_exists" ]; then
  echo -e "${RED}Error: Project $PROJECT_ID does not exist. Run bootstrap.sh first to create it.${NC}"
  exit 1
fi

# Check if user has access to the project
echo -e "${BLUE}Checking permissions on project $PROJECT_ID...${NC}"
if ! gcloud projects get-iam-policy $PROJECT_ID &>/dev/null; then
  echo -e "${RED}Error: You don't have sufficient permissions on project $PROJECT_ID.${NC}"
  exit 1
fi

# Print settings
echo -e "${GREEN}Deployment Settings:${NC}"
echo -e "${GREEN}  Environment:${NC} $ENVIRONMENT"
echo -e "${GREEN}  Project ID:${NC} $PROJECT_ID"
echo -e "${GREEN}  Components:${NC} $COMPONENTS"
if [ "$ENVIRONMENT" == "dev" ]; then
  echo -e "${GREEN}  Developer:${NC} $DEVELOPER_NAME"
fi

# Confirm with user unless --yes flag is used
if [ "$SKIP_CONFIRM" != "true" ]; then
  echo ""
  read -p "Do you want to continue with the deployment? (y/n) " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment canceled."
    exit 0
  fi
fi

# Run deployments for all environments if --all_envs is specified
if [ "$ALL_ENVS" == "true" ]; then
  echo -e "${BLUE}Starting deployment to all environments...${NC}"
  
  # Save original settings
  ORIGINAL_ENV=$ENVIRONMENT
  ORIGINAL_CONFIRM=$SKIP_CONFIRM
  
  # Always skip confirmation for individual deployments when deploying to all envs
  SKIP_CONFIRM=true
  
  # Deploy to dev
  echo -e "${YELLOW}=== Deploying to DEV environment ===${NC}"
  ENVIRONMENT="dev"
  
  # Set the project ID based on environment
  if [ "$ENVIRONMENT" == "dev" ]; then
    PROJECT_ID="${PROJECT_NAME}-${ENVIRONMENT}-${DEVELOPER_NAME}"
  else
    PROJECT_ID="${PROJECT_NAME}-${ENVIRONMENT}"
  fi
  
  # Check if the project exists
  echo -e "${BLUE}Checking if project $PROJECT_ID exists...${NC}"
  project_exists=$(gcloud projects list --format="value(projectId)" --filter="projectId=$PROJECT_ID" 2>/dev/null || echo "")
  
  if [ -z "$project_exists" ]; then
    echo -e "${RED}Error: Project $PROJECT_ID does not exist. Skipping dev environment.${NC}"
  else
    # Check if user has access to the project
    echo -e "${BLUE}Checking permissions on project $PROJECT_ID...${NC}"
    if ! gcloud projects get-iam-policy $PROJECT_ID &>/dev/null; then
      echo -e "${RED}Error: You don't have sufficient permissions on project $PROJECT_ID. Skipping dev environment.${NC}"
    else
      echo -e "${GREEN}Deploying to $PROJECT_ID...${NC}"
      
      # Set GCP project
      echo -e "${GREEN}Setting GCP project to $PROJECT_ID...${NC}"
      gcloud config set project $PROJECT_ID
      
      # Bootstrap Firebase for the project
      echo -e "${YELLOW}Bootstrapping Firebase resources...${NC}"
      if [ -f ./scripts/bootstrap_firebase.sh ]; then
        ./scripts/bootstrap_firebase.sh --${ENVIRONMENT} --yes
        if [ $? -ne 0 ]; then
          echo -e "${RED}Firebase bootstrap failed. Check the logs above.${NC}"
          echo -e "${YELLOW}Continuing with deployment, but Firebase features may not work properly.${NC}"
        fi
      else
        echo -e "${YELLOW}Firebase bootstrap script not found. Skipping Firebase setup.${NC}"
        echo -e "${YELLOW}You may need to manually configure Firebase resources.${NC}"
      fi
      
      # Deploy components
      if [ "$COMPONENTS" == "backend" ] || [ "$COMPONENTS" == "all" ]; then
        echo -e "${GREEN}Building and deploying backend...${NC}"
        
        # Build the backend container
        BACKEND_IMAGE="gcr.io/$PROJECT_ID/backend:$ENVIRONMENT"
        gcloud builds submit backend --tag $BACKEND_IMAGE
        
        # Deploy to Cloud Run
        gcloud run deploy backend-api \
          --image $BACKEND_IMAGE \
          --platform managed \
          --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') \
          --allow-unauthenticated \
          --set-env-vars="ENVIRONMENT=$ENVIRONMENT"
          
        echo -e "${GREEN}Backend deployed successfully!${NC}"
      fi
      
      # Build and deploy frontend
      if [ "$COMPONENTS" == "frontend" ] || [ "$COMPONENTS" == "all" ]; then
        echo -e "${GREEN}Building and deploying frontend...${NC}"
        
        # Get backend URL
        BACKEND_URL=$(gcloud run services describe backend-api --platform managed --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') --format "value(status.url)")
        
        # Build the Docker image
        FRONTEND_IMAGE="gcr.io/$PROJECT_ID/frontend:$ENVIRONMENT"
        # Use a Cloud Build configuration file approach
        cat > cloudbuild.yaml <<EOF
steps:
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '$FRONTEND_IMAGE', '--build-arg', 'BACKEND_URL=$BACKEND_URL', 'frontend/']
images:
- '$FRONTEND_IMAGE'
EOF
        gcloud builds submit --config cloudbuild.yaml
        
        # Deploy to Cloud Run
        gcloud run deploy frontend-web \
          --image $FRONTEND_IMAGE \
          --platform managed \
          --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') \
          --allow-unauthenticated \
          --set-env-vars="NODE_ENV=$ENVIRONMENT,BACKEND_URL=$BACKEND_URL,NEXT_PUBLIC_BACKEND_URL=$BACKEND_URL"
          
        echo -e "${GREEN}Frontend deployed successfully!${NC}"
      fi
      
      # Get URLs
      if [ "$COMPONENTS" == "backend" ] || [ "$COMPONENTS" == "all" ]; then
        BACKEND_URL=$(gcloud run services describe backend-api --platform managed --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') --format "value(status.url)")
        echo -e "${GREEN}Backend URL:${NC} $BACKEND_URL"
      fi
      
      if [ "$COMPONENTS" == "frontend" ] || [ "$COMPONENTS" == "all" ]; then
        FRONTEND_URL=$(gcloud run services describe frontend-web --platform managed --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') --format "value(status.url)")
        echo -e "${GREEN}Frontend URL:${NC} $FRONTEND_URL"
      fi
      
      # Generate a URL file
      if [ -n "$BACKEND_URL" ] || [ -n "$FRONTEND_URL" ]; then
        URL_FILE="urls.$ENVIRONMENT.json"
        echo "{" > $URL_FILE
        echo "  \"environment\": \"$ENVIRONMENT\"," >> $URL_FILE
        echo "  \"projectId\": \"$PROJECT_ID\"," >> $URL_FILE
        if [ -n "$BACKEND_URL" ]; then
          echo "  \"backendUrl\": \"$BACKEND_URL\"," >> $URL_FILE
        fi
        if [ -n "$FRONTEND_URL" ]; then
          echo "  \"frontendUrl\": \"$FRONTEND_URL\"" >> $URL_FILE
        fi
        echo "}" >> $URL_FILE
        
        echo -e "${GREEN}Saved URLs to $URL_FILE${NC}"
        
        # If this is a development environment, also write to local dev config
        if [ "$ENVIRONMENT" == "dev" ]; then
          echo "{" > urls/urls.local.json
          echo "  \"environment\": \"$ENVIRONMENT\"," >> urls/urls.local.json
          echo "  \"projectId\": \"$PROJECT_ID\"," >> urls/urls.local.json
          if [ -n "$BACKEND_URL" ]; then
            echo "  \"backendUrl\": \"$BACKEND_URL\"," >> urls/urls.local.json
          fi
          if [ -n "$FRONTEND_URL" ]; then
            echo "  \"frontendUrl\": \"$FRONTEND_URL\"" >> urls/urls.local.json
          fi
          echo "}" >> urls/urls.local.json
          echo -e "${GREEN}Saved development URLs to urls/urls.local.json (for local development)${NC}"
        fi
      fi
      
      echo -e "${GREEN}Deployment complete for $ENVIRONMENT environment!${NC}" 
      echo ""
    fi
  fi
  
  # Deploy to staging
  echo -e "${YELLOW}=== Deploying to STAGING environment ===${NC}"
  ENVIRONMENT="staging"
  
  # Set the project ID based on environment
  PROJECT_ID="${PROJECT_NAME}-${ENVIRONMENT}"
  
  # Check if the project exists
  echo -e "${BLUE}Checking if project $PROJECT_ID exists...${NC}"
  project_exists=$(gcloud projects list --format="value(projectId)" --filter="projectId=$PROJECT_ID" 2>/dev/null || echo "")
  
  if [ -z "$project_exists" ]; then
    echo -e "${RED}Error: Project $PROJECT_ID does not exist. Skipping staging environment.${NC}"
  else
    # Check if user has access to the project
    echo -e "${BLUE}Checking permissions on project $PROJECT_ID...${NC}"
    if ! gcloud projects get-iam-policy $PROJECT_ID &>/dev/null; then
      echo -e "${RED}Error: You don't have sufficient permissions on project $PROJECT_ID. Skipping staging environment.${NC}"
    else
      echo -e "${GREEN}Deploying to $PROJECT_ID...${NC}"
      
      # Set GCP project
      echo -e "${GREEN}Setting GCP project to $PROJECT_ID...${NC}"
      gcloud config set project $PROJECT_ID
      
      # Bootstrap Firebase for the project
      echo -e "${YELLOW}Bootstrapping Firebase resources...${NC}"
      if [ -f ./scripts/bootstrap_firebase.sh ]; then
        ./scripts/bootstrap_firebase.sh --${ENVIRONMENT} --yes
        if [ $? -ne 0 ]; then
          echo -e "${RED}Firebase bootstrap failed. Check the logs above.${NC}"
          echo -e "${YELLOW}Continuing with deployment, but Firebase features may not work properly.${NC}"
        fi
      else
        echo -e "${YELLOW}Firebase bootstrap script not found. Skipping Firebase setup.${NC}"
        echo -e "${YELLOW}You may need to manually configure Firebase resources.${NC}"
      fi
      
      # Deploy components
      if [ "$COMPONENTS" == "backend" ] || [ "$COMPONENTS" == "all" ]; then
        echo -e "${GREEN}Building and deploying backend...${NC}"
        
        # Build the backend container
        BACKEND_IMAGE="gcr.io/$PROJECT_ID/backend:$ENVIRONMENT"
        gcloud builds submit backend --tag $BACKEND_IMAGE
        
        # Deploy to Cloud Run
        gcloud run deploy backend-api \
          --image $BACKEND_IMAGE \
          --platform managed \
          --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') \
          --allow-unauthenticated \
          --set-env-vars="ENVIRONMENT=$ENVIRONMENT"
          
        echo -e "${GREEN}Backend deployed successfully!${NC}"
      fi
      
      # Build and deploy frontend
      if [ "$COMPONENTS" == "frontend" ] || [ "$COMPONENTS" == "all" ]; then
        echo -e "${GREEN}Building and deploying frontend...${NC}"
        
        # Get backend URL
        BACKEND_URL=$(gcloud run services describe backend-api --platform managed --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') --format "value(status.url)")
        
        # Build the Docker image
        FRONTEND_IMAGE="gcr.io/$PROJECT_ID/frontend:$ENVIRONMENT"
        # Use a Cloud Build configuration file approach
        cat > cloudbuild.yaml <<EOF
steps:
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '$FRONTEND_IMAGE', '--build-arg', 'BACKEND_URL=$BACKEND_URL', 'frontend/']
images:
- '$FRONTEND_IMAGE'
EOF
        gcloud builds submit --config cloudbuild.yaml
        
        # Deploy to Cloud Run
        gcloud run deploy frontend-web \
          --image $FRONTEND_IMAGE \
          --platform managed \
          --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') \
          --allow-unauthenticated \
          --set-env-vars="NODE_ENV=$ENVIRONMENT,BACKEND_URL=$BACKEND_URL,NEXT_PUBLIC_BACKEND_URL=$BACKEND_URL"
          
        echo -e "${GREEN}Frontend deployed successfully!${NC}"
      fi
      
      # Get URLs
      if [ "$COMPONENTS" == "backend" ] || [ "$COMPONENTS" == "all" ]; then
        BACKEND_URL=$(gcloud run services describe backend-api --platform managed --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') --format "value(status.url)")
        echo -e "${GREEN}Backend URL:${NC} $BACKEND_URL"
      fi
      
      if [ "$COMPONENTS" == "frontend" ] || [ "$COMPONENTS" == "all" ]; then
        FRONTEND_URL=$(gcloud run services describe frontend-web --platform managed --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') --format "value(status.url)")
        echo -e "${GREEN}Frontend URL:${NC} $FRONTEND_URL"
      fi
      
      # Generate a URL file
      if [ -n "$BACKEND_URL" ] || [ -n "$FRONTEND_URL" ]; then
        URL_FILE="urls.$ENVIRONMENT.json"
        echo "{" > $URL_FILE
        echo "  \"environment\": \"$ENVIRONMENT\"," >> $URL_FILE
        echo "  \"projectId\": \"$PROJECT_ID\"," >> $URL_FILE
        if [ -n "$BACKEND_URL" ]; then
          echo "  \"backendUrl\": \"$BACKEND_URL\"," >> $URL_FILE
        fi
        if [ -n "$FRONTEND_URL" ]; then
          echo "  \"frontendUrl\": \"$FRONTEND_URL\"" >> $URL_FILE
        fi
        echo "}" >> $URL_FILE
        
        echo -e "${GREEN}Saved URLs to $URL_FILE${NC}"
      fi
      
      echo -e "${GREEN}Deployment complete for $ENVIRONMENT environment!${NC}" 
      echo ""
    fi
  fi
  
  # Deploy to prod
  echo -e "${YELLOW}=== Deploying to PRODUCTION environment ===${NC}"
  ENVIRONMENT="prod"
  
  # Set the project ID based on environment
  PROJECT_ID="${PROJECT_NAME}-${ENVIRONMENT}"
  
  # Check if the project exists
  echo -e "${BLUE}Checking if project $PROJECT_ID exists...${NC}"
  project_exists=$(gcloud projects list --format="value(projectId)" --filter="projectId=$PROJECT_ID" 2>/dev/null || echo "")
  
  if [ -z "$project_exists" ]; then
    echo -e "${RED}Error: Project $PROJECT_ID does not exist. Skipping production environment.${NC}"
  else
    # Check if user has access to the project
    echo -e "${BLUE}Checking permissions on project $PROJECT_ID...${NC}"
    if ! gcloud projects get-iam-policy $PROJECT_ID &>/dev/null; then
      echo -e "${RED}Error: You don't have sufficient permissions on project $PROJECT_ID. Skipping production environment.${NC}"
    else
      echo -e "${GREEN}Deploying to $PROJECT_ID...${NC}"
      
      # Set GCP project
      echo -e "${GREEN}Setting GCP project to $PROJECT_ID...${NC}"
      gcloud config set project $PROJECT_ID
      
      # Bootstrap Firebase for the project
      echo -e "${YELLOW}Bootstrapping Firebase resources...${NC}"
      if [ -f ./scripts/bootstrap_firebase.sh ]; then
        ./scripts/bootstrap_firebase.sh --${ENVIRONMENT} --yes
        if [ $? -ne 0 ]; then
          echo -e "${RED}Firebase bootstrap failed. Check the logs above.${NC}"
          echo -e "${YELLOW}Continuing with deployment, but Firebase features may not work properly.${NC}"
        fi
      else
        echo -e "${YELLOW}Firebase bootstrap script not found. Skipping Firebase setup.${NC}"
        echo -e "${YELLOW}You may need to manually configure Firebase resources.${NC}"
      fi
      
      # Deploy components
      if [ "$COMPONENTS" == "backend" ] || [ "$COMPONENTS" == "all" ]; then
        echo -e "${GREEN}Building and deploying backend...${NC}"
        
        # Build the backend container
        BACKEND_IMAGE="gcr.io/$PROJECT_ID/backend:$ENVIRONMENT"
        gcloud builds submit backend --tag $BACKEND_IMAGE
        
        # Deploy to Cloud Run
        gcloud run deploy backend-api \
          --image $BACKEND_IMAGE \
          --platform managed \
          --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') \
          --allow-unauthenticated \
          --set-env-vars="ENVIRONMENT=$ENVIRONMENT"
          
        echo -e "${GREEN}Backend deployed successfully!${NC}"
      fi
      
      # Build and deploy frontend
      if [ "$COMPONENTS" == "frontend" ] || [ "$COMPONENTS" == "all" ]; then
        echo -e "${GREEN}Building and deploying frontend...${NC}"
        
        # Get backend URL
        BACKEND_URL=$(gcloud run services describe backend-api --platform managed --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') --format "value(status.url)")
        
        # Build the Docker image
        FRONTEND_IMAGE="gcr.io/$PROJECT_ID/frontend:$ENVIRONMENT"
        # Use a Cloud Build configuration file approach
        cat > cloudbuild.yaml <<EOF
steps:
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '$FRONTEND_IMAGE', '--build-arg', 'BACKEND_URL=$BACKEND_URL', 'frontend/']
images:
- '$FRONTEND_IMAGE'
EOF
        gcloud builds submit --config cloudbuild.yaml
        
        # Deploy to Cloud Run
        gcloud run deploy frontend-web \
          --image $FRONTEND_IMAGE \
          --platform managed \
          --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') \
          --allow-unauthenticated \
          --set-env-vars="NODE_ENV=$ENVIRONMENT,BACKEND_URL=$BACKEND_URL,NEXT_PUBLIC_BACKEND_URL=$BACKEND_URL"
          
        echo -e "${GREEN}Frontend deployed successfully!${NC}"
      fi
      
      # Get URLs
      if [ "$COMPONENTS" == "backend" ] || [ "$COMPONENTS" == "all" ]; then
        BACKEND_URL=$(gcloud run services describe backend-api --platform managed --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') --format "value(status.url)")
        echo -e "${GREEN}Backend URL:${NC} $BACKEND_URL"
      fi
      
      if [ "$COMPONENTS" == "frontend" ] || [ "$COMPONENTS" == "all" ]; then
        FRONTEND_URL=$(gcloud run services describe frontend-web --platform managed --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') --format "value(status.url)")
        echo -e "${GREEN}Frontend URL:${NC} $FRONTEND_URL"
      fi
      
      # Generate a URL file
      if [ -n "$BACKEND_URL" ] || [ -n "$FRONTEND_URL" ]; then
        URL_FILE="urls.$ENVIRONMENT.json"
        echo "{" > $URL_FILE
        echo "  \"environment\": \"$ENVIRONMENT\"," >> $URL_FILE
        echo "  \"projectId\": \"$PROJECT_ID\"," >> $URL_FILE
        if [ -n "$BACKEND_URL" ]; then
          echo "  \"backendUrl\": \"$BACKEND_URL\"," >> $URL_FILE
        fi
        if [ -n "$FRONTEND_URL" ]; then
          echo "  \"frontendUrl\": \"$FRONTEND_URL\"" >> $URL_FILE
        fi
        echo "}" >> $URL_FILE
        
        echo -e "${GREEN}Saved URLs to $URL_FILE${NC}"
      fi
      
      echo -e "${GREEN}Deployment complete for $ENVIRONMENT environment!${NC}" 
      echo ""
    fi
  fi
  
  # Print summary
  echo -e "${GREEN}All deployments completed successfully!${NC}"
  echo -e "${BLUE}URLs can be found in: ${NC}"
  echo -e "  - urls/urls.dev.json"
  echo -e "  - urls/urls.staging.json"
  echo -e "  - urls/urls.prod.json"
  echo -e "  - urls/urls.local.json (for local development)"
  
  # Restore original environment
  ENVIRONMENT=$ORIGINAL_ENV
  SKIP_CONFIRM=$ORIGINAL_CONFIRM
  
  # Exit after deploying to all environments
  exit 0
fi

# If not deploying to all environments, continue with single environment deployment

# Set GCP project
echo -e "${GREEN}Setting GCP project to $PROJECT_ID...${NC}"
gcloud config set project $PROJECT_ID

# Bootstrap Firebase for the project
echo -e "${YELLOW}Bootstrapping Firebase resources...${NC}"
if [ -f ./scripts/bootstrap_firebase.sh ]; then
  ./scripts/bootstrap_firebase.sh --${ENVIRONMENT} --yes
  if [ $? -ne 0 ]; then
    echo -e "${RED}Firebase bootstrap failed. Check the logs above.${NC}"
    echo -e "${YELLOW}Continuing with deployment, but Firebase features may not work properly.${NC}"
  fi
else
  echo -e "${YELLOW}Firebase bootstrap script not found. Skipping Firebase setup.${NC}"
  echo -e "${YELLOW}You may need to manually configure Firebase resources.${NC}"
fi

# Build and deploy backend
if [ "$COMPONENTS" == "backend" ] || [ "$COMPONENTS" == "all" ]; then
  echo -e "${GREEN}Building and deploying backend...${NC}"
  
  # Build the backend container
  # Build the Docker image
  BACKEND_IMAGE="gcr.io/$PROJECT_ID/backend:$ENVIRONMENT"
  gcloud builds submit backend --tag $BACKEND_IMAGE
  
  # Deploy to Cloud Run
  gcloud run deploy backend-api \
    --image $BACKEND_IMAGE \
    --platform managed \
    --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') \
    --allow-unauthenticated \
    --set-env-vars="ENVIRONMENT=$ENVIRONMENT"
    
  echo -e "${GREEN}Backend deployed successfully!${NC}"
fi

# Build and deploy frontend
if [ "$COMPONENTS" == "frontend" ] || [ "$COMPONENTS" == "all" ]; then
  echo -e "${GREEN}Building and deploying frontend...${NC}"
  
  # Get backend URL
  BACKEND_URL=$(gcloud run services describe backend-api --platform managed --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') --format "value(status.url)")
  
  # Build the Docker image
  FRONTEND_IMAGE="gcr.io/$PROJECT_ID/frontend:$ENVIRONMENT"
  # Use a Cloud Build configuration file approach
  cat > cloudbuild.yaml <<EOF
steps:
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '$FRONTEND_IMAGE', '--build-arg', 'BACKEND_URL=$BACKEND_URL', 'frontend/']
images:
- '$FRONTEND_IMAGE'
EOF
  gcloud builds submit --config cloudbuild.yaml
  
  # Deploy to Cloud Run
  gcloud run deploy frontend-web \
    --image $FRONTEND_IMAGE \
    --platform managed \
    --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') \
    --allow-unauthenticated \
    --set-env-vars="NODE_ENV=$ENVIRONMENT,BACKEND_URL=$BACKEND_URL,NEXT_PUBLIC_BACKEND_URL=$BACKEND_URL"
    
  echo -e "${GREEN}Frontend deployed successfully!${NC}"
fi

# Get URLs
if [ "$COMPONENTS" == "backend" ] || [ "$COMPONENTS" == "all" ]; then
  BACKEND_URL=$(gcloud run services describe backend-api --platform managed --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') --format "value(status.url)")
  echo -e "${GREEN}Backend URL:${NC} $BACKEND_URL"
fi

if [ "$COMPONENTS" == "frontend" ] || [ "$COMPONENTS" == "all" ]; then
  FRONTEND_URL=$(gcloud run services describe frontend-web --platform managed --region $(grep "region:" config.yaml | head -n1 | sed 's/.*region: //' | sed 's/"//g') --format "value(status.url)")
  echo -e "${GREEN}Frontend URL:${NC} $FRONTEND_URL"
fi

# Generate a URL file
if [ -n "$BACKEND_URL" ] || [ -n "$FRONTEND_URL" ]; then
  URL_FILE="urls.$ENVIRONMENT.json"
  echo "{" > $URL_FILE
  echo "  \"environment\": \"$ENVIRONMENT\"," >> $URL_FILE
  echo "  \"projectId\": \"$PROJECT_ID\"," >> $URL_FILE
  if [ -n "$BACKEND_URL" ]; then
    echo "  \"backendUrl\": \"$BACKEND_URL\"," >> $URL_FILE
  fi
  if [ -n "$FRONTEND_URL" ]; then
    echo "  \"frontendUrl\": \"$FRONTEND_URL\"" >> $URL_FILE
  fi
  echo "}" >> $URL_FILE
  
  echo -e "${GREEN}Saved URLs to $URL_FILE${NC}"
  
  # If this is a development environment, also write to local dev config
  if [ "$ENVIRONMENT" == "dev" ]; then
    echo "{" > urls/urls.local.json
    echo "  \"environment\": \"$ENVIRONMENT\"," >> urls/urls.local.json
    echo "  \"projectId\": \"$PROJECT_ID\"," >> urls/urls.local.json
    if [ -n "$BACKEND_URL" ]; then
      echo "  \"backendUrl\": \"$BACKEND_URL\"," >> urls/urls.local.json
    fi
    if [ -n "$FRONTEND_URL" ]; then
      echo "  \"frontendUrl\": \"$FRONTEND_URL\"" >> urls/urls.local.json
    fi
    echo "}" >> urls/urls.local.json
    echo -e "${GREEN}Saved development URLs to urls/urls.local.json (for local development)${NC}"
  fi
fi

echo -e "${GREEN}Deployment complete for $ENVIRONMENT environment!${NC}" 