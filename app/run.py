# FastAPI entry point
import os
import re
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import logging

# Read values from config file
def get_config_value(key, default=None):
    try:
        with open('config', 'r') as config_file:
            for line in config_file:
                if line.startswith(f'{key}:'):
                    match = re.search(r"['\"](.*)['\"]", line)
                    if match:
                        return match.group(1)
    except Exception as e:
        logging.error(f"Error reading config file: {e}")
    return default

# Get project ID and other configuration
project_id = get_config_value('gcp_project_id', 'unnamed-project')
service_name = get_config_value('service_name', 'api')
api_title = f"{service_name.replace('-', ' ').title()} API"

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

# Get environment
environment: str = os.getenv("ENVIRONMENT", "development")
logger.info(f"Starting API in {environment} environment")

@app.get("/")
async def root():
    return {
        "message": f"Welcome to {api_title}",
        "environment": environment,
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
