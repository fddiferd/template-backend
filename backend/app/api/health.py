from fastapi import APIRouter, Depends
from datetime import datetime
import platform
import os
import psutil

router = APIRouter(
    prefix="/api/health",
    tags=["health"],
    responses={404: {"description": "Not found"}},
)

def get_system_info():
    """Gather system information for health reporting"""
    return {
        "python_version": platform.python_version(),
        "platform": platform.platform(),
        "processor": platform.processor(),
        "cpu_usage": psutil.cpu_percent(interval=0.1),
        "memory_usage": psutil.virtual_memory().percent,
        "disk_usage": psutil.disk_usage('/').percent
    }

@router.get("/")
async def health_check():
    """
    Comprehensive health check endpoint
    Returns detailed information about API health and system status
    """
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "version": os.environ.get("APP_VERSION", "0.1.0"),
        "environment": os.environ.get("ENVIRONMENT", "development"),
        "system_info": get_system_info()
    }

@router.get("/live")
async def liveness_check():
    """
    Liveness probe for Kubernetes/Cloud Run
    Used to determine if the application is running and responsive
    """
    return {"status": "alive"}

@router.get("/ready")
async def readiness_check():
    """
    Readiness probe for Kubernetes/Cloud Run
    Used to determine if the application is ready to receive traffic
    """
    return {"status": "ready"} 