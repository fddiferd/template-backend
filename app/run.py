# FastAPI entry point
import os
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import logging



# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger: logging.Logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title="Wedge Golf API",
    description="Backend API for Wedge Golf",
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
        "message": "Welcome to Wedge Golf API",
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
        "service": "Wedge Golf API",
        "environment": environment,
        "version": "0.1.0",
        "unauthenticated": True
    }
