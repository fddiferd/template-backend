# FastAPI entry point
import os
import re
from fastapi import FastAPI, Depends, HTTPException, Body
from fastapi.middleware.cors import CORSMiddleware
import logging
from typing import Dict, Any, List, Optional
from pydantic import BaseModel

# Import Firebase utilities
from app.firebase_utils import (
    create_customer, 
    get_customer, 
    update_customer, 
    delete_customer, 
    list_customers
)

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

# Define Pydantic models
class CustomerBase(BaseModel):
    name: str
    email: str
    phone: Optional[str] = None
    address: Optional[Dict[str, Any]] = None
    
class CustomerCreate(CustomerBase):
    pass
    
class CustomerUpdate(CustomerBase):
    name: Optional[str] = None
    email: Optional[str] = None
    
class CustomerResponse(CustomerBase):
    id: str
    
    class Config:
        orm_mode = True

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

@app.get("/cicd-test")
async def cicd_test():
    return {"ci": "cd", "test": "test", "3": "3"}

# Add your API routes here
@app.get("/api/v1/status")
async def status():
    return {
        "service": api_title,
        "environment": environment,
        "version": "0.1.0",
        "unauthenticated": True
    }

# Customer API routes
@app.post("/api/customer", response_model=Dict[str, Any])
async def create_customer_endpoint(customer: CustomerCreate = Body(...)):
    """Create a new customer in Firestore"""
    customer_id = create_customer(customer.dict())
    if not customer_id:
        raise HTTPException(status_code=500, detail="Failed to create customer")
    
    # Get the created customer
    customer_data = get_customer(customer_id)
    if not customer_data:
        raise HTTPException(status_code=500, detail="Customer created but couldn't retrieve it")
    
    # Add ID to the customer data safely
    result = {}
    if customer_data and isinstance(customer_data, dict):
        result = dict(customer_data)
    result["id"] = customer_id
    
    return {
        "success": True,
        "id": customer_id,
        "customer": result
    }

@app.post("/api/customer/test", response_model=Dict[str, Any])
async def create_test_customer():
    """Create a test customer in Firestore"""
    test_customer = {
        "name": "Test Customer",
        "email": "test@example.com",
        "phone": "555-123-4567",
        "address": {
            "street": "123 Test St",
            "city": "Test City",
            "state": "TS",
            "zip": "12345"
        }
    }
    
    customer_id = create_customer(test_customer)
    if not customer_id:
        raise HTTPException(status_code=500, detail="Failed to create test customer")
    
    # Get the created customer
    customer_data = get_customer(customer_id)
    if not customer_data:
        raise HTTPException(status_code=500, detail="Test customer created but couldn't retrieve it")
    
    # Add ID to the customer data safely
    result = {}
    if customer_data and isinstance(customer_data, dict):
        result = dict(customer_data)
    result["id"] = customer_id
    
    return {
        "success": True,
        "id": customer_id,
        "customer": result
    }

@app.get("/api/customer/{customer_id}", response_model=Dict[str, Any])
async def get_customer_endpoint(customer_id: str):
    """Get a customer by ID"""
    customer_data = get_customer(customer_id)
    if not customer_data:
        raise HTTPException(status_code=404, detail=f"Customer with ID {customer_id} not found")
    
    # Add ID to the customer data safely
    result = {}
    if isinstance(customer_data, dict):
        result = dict(customer_data)
    result["id"] = customer_id
    
    return {
        "success": True,
        "customer": result
    }

@app.get("/api/customers", response_model=Dict[str, Any])
async def list_customers_endpoint(limit: int = 100):
    """List all customers"""
    customers_data = list_customers(limit)
    
    return {
        "success": True,
        "count": len(customers_data),
        "customers": customers_data
    }

@app.put("/api/customer/{customer_id}", response_model=Dict[str, Any])
async def update_customer_endpoint(customer_id: str, customer_update: CustomerUpdate = Body(...)):
    """Update a customer"""
    # First check if customer exists
    existing_customer = get_customer(customer_id)
    if not existing_customer:
        raise HTTPException(status_code=404, detail=f"Customer with ID {customer_id} not found")
    
    # Filter out None values
    update_data = {k: v for k, v in customer_update.dict().items() if v is not None}
    
    # Update the customer
    success = update_customer(customer_id, update_data)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to update customer")
    
    # Get updated customer
    updated_customer = get_customer(customer_id)
    
    # Add ID to the customer data safely
    result = {}
    if updated_customer and isinstance(updated_customer, dict):
        result = dict(updated_customer)
    result["id"] = customer_id
    
    return {
        "success": True,
        "customer": result
    }

@app.delete("/api/customer/{customer_id}", response_model=Dict[str, Any])
async def delete_customer_endpoint(customer_id: str):
    """Delete a customer"""
    # First check if customer exists
    existing_customer = get_customer(customer_id)
    if not existing_customer:
        raise HTTPException(status_code=404, detail=f"Customer with ID {customer_id} not found")
    
    # Delete the customer
    success = delete_customer(customer_id)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to delete customer")
    
    return {
        "success": True,
        "message": f"Customer with ID {customer_id} deleted successfully"
    }
