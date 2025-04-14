from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from firebase_admin import credentials, firestore, initialize_app
import os
import json
from datetime import datetime
import uvicorn
import yaml

# Import routers
from app.api.health import router as health_router
from app.api.customers import router as customers_router

# Load configuration
def load_config():
    """
    Load configuration from config.yaml file or environment variables
    """
    # Try to find config in the relative path from the app
    config_path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), 'config.yaml')
    
    try:
        if os.path.exists(config_path):
            with open(config_path, 'r') as file:
                return yaml.safe_load(file)
        elif os.path.exists('/config.yaml'):
            with open('/config.yaml', 'r') as file:
                return yaml.safe_load(file)
    except Exception:
        pass
        
    # Fall back to environment variables
    project_name = os.environ.get('PROJECT_NAME', 'app')
    project_id = os.environ.get('PROJECT_ID', 'app')
    return {
        'project': {
            'name': project_name,
            'id': project_id,
            'description': f'{project_name} Application',
            'region': os.environ.get('REGION', 'us-central1'),
            'zone': os.environ.get('ZONE', 'us-central1-a')
        },
        'application': {
            'backend': {
                'name': f'{project_id}-api',
                'port': int(os.environ.get('PORT', 8080))
            },
            'frontend': {
                'name': f'{project_id}-web',
                'port': int(os.environ.get('FRONTEND_PORT', 3000))
            }
        }
    }

config = load_config()

# Get environment
ENVIRONMENT = os.environ.get("ENVIRONMENT", "development")
if ENVIRONMENT == "development":
    ENV_SHORT = "dev"
elif ENVIRONMENT == "staging":
    ENV_SHORT = "staging"
else:
    ENV_SHORT = "prod"

# Initialize FastAPI
app = FastAPI(
    title=f"{config['project']['name']} API",
    description=f"Backend API for {config['project']['description']}",
    version="0.1.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, replace with specific origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(health_router)
app.include_router(customers_router)

# Initialize Firebase if credentials exist
firebase_initialized = False
firebase_app = None

@app.on_event("startup")
async def startup_db_client():
    global firebase_initialized
    global firebase_app
    
    try:
        # Import here to avoid circular imports
        import firebase_admin
        from firebase_admin import firestore
        
        # Check if Firebase is already initialized
        try:
            firebase_app = firebase_admin.get_app()
            print("Existing Firebase app found and will be used")
            firebase_initialized = True
        except ValueError:
            # Initialize with minimal config
            firebase_app = firebase_admin.initialize_app()
            print("Firebase initialized with default configuration")
            firebase_initialized = True
        
        # Test connection
        firestore.client()
        print("Firestore client initialized successfully")
        
    except Exception as e:
        print(f"Error initializing Firebase: {e}")
        import traceback
        traceback.print_exc()

@app.get("/")
async def root():
    return {"message": "Welcome to Backend API"}

@app.get("/health")
async def basic_health_check():
    """
    Simple health check endpoint at the root level
    """
    return {
        "status": "ok",
        "timestamp": datetime.now().isoformat(),
        "environment": ENVIRONMENT,
        "project_id": os.environ.get("GCP_PROJECT_ID", "local"),
        "dependencies": {
            "firebase": "connected" if firebase_initialized else "not_connected"
        }
    }

@app.get("/api/ready")
async def readiness_check():
    """
    Readiness probe for Kubernetes/Cloud Run
    """
    return {"status": "ready"}

if __name__ == "__main__":
    # Get port from environment variable or use default from config
    port = int(os.environ.get("PORT", config['application']['backend']['port']))
    uvicorn.run("app.main:app", host="0.0.0.0", port=port, reload=True) 