# FastAPI entry point
import os
import re
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import logging

# Read values from config file
def get_config_value(key, default=None):
    try:
        config_paths = ['config', '/app/config']  # Try both local and Docker path
        for config_path in config_paths:
            if os.path.exists(config_path):
                with open(config_path, 'r') as config_file:
                    for line in config_file:
                        if line.startswith(f'{key}:'):
                            match = re.search(r"['\"](.*)['\"]", line)
                            if match:
                                value = match.group(1)
                                logging.info(f"Config: Found {key}={value} in {config_path}")
                                return value
                logging.warning(f"Config: Key '{key}' not found in {config_path}")
            else:
                logging.warning(f"Config: File {config_path} not found")
    except Exception as e:
        logging.error(f"Error reading config file: {e}")
    
    logging.warning(f"Config: Using default value for {key}={default}")
    return default

# Get environment
environment: str = os.getenv("ENVIRONMENT", "development")
logging.info(f"Starting API in {environment} environment")

# Get project ID and other configuration
project_id = get_config_value('gcp_project_id', 'unnamed-project')
service_name = get_config_value('service_name', 'api')

# Format the service name into a properly capitalized title
if service_name:
    # Replace both hyphens and underscores with spaces
    formatted_name = service_name.replace('-', ' ').replace('_', ' ')

    # Capitalize each word
    formatted_name = ' '.join(word.capitalize() for word in formatted_name.split())

    # Avoid duplicate "API" in the title
    if service_name.lower().endswith('api'):
        # If service name already contains "api", just use the formatted name
        api_title = formatted_name
    else:
        # Otherwise add "API" suffix
        api_title = f"{formatted_name} API"
else:
    # Fallback for safety
    formatted_name = "Api"
    api_title = "Api"

logging.info(f"API Title: {api_title}, Environment: {environment}")

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger: logging.Logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title=api_title,
    description=f"Backend API for {project_id}",
    version="0.1.0",
)

# Set up CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, you might want to restrict this
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
async def root():
    return {
        "message": f"Welcome to {formatted_name} (CI/CD Test)",
        "environment": environment,
        "project_id": project_id,
        "service_name": service_name,
        "status": "healthy"
    }

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

# Add your API routes here
@app.get("/api/v1/status")
async def status():
    return {
        "service": api_title,
        "environment": environment,
        "version": "0.1.0",
        "unauthenticated": True
    }
