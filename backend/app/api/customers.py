from fastapi import APIRouter, HTTPException, Body
from typing import List, Optional, Dict, Any
from datetime import datetime
import uuid
from google.cloud.firestore_v1.client import Client
from pydantic import BaseModel
from app.db import get_db

router = APIRouter(
    prefix="/api/customers",
    tags=["customers"],
    responses={404: {"description": "Not found"}}
)

# Customer model
class Customer:
    def __init__(self, id: str, first_name: str, last_name: str, email: Optional[str] = None,
                 created_at: Optional[str] = None, updated_at: Optional[str] = None):
        self.id = id
        self.first_name = first_name
        self.last_name = last_name
        self.email = email
        self.created_at = created_at or datetime.now().isoformat()
        self.updated_at = updated_at or datetime.now().isoformat()
    
    @classmethod
    def from_dict(cls, id: str, data: Dict[str, Any]):
        return cls(
            id=id,
            first_name=str(data.get("first_name", "")),
            last_name=str(data.get("last_name", "")),
            email=data.get("email"),
            created_at=data.get("created_at"),
            updated_at=data.get("updated_at")
        )
    
    def to_dict(self):
        return {
            "id": self.id,
            "first_name": self.first_name,
            "last_name": self.last_name,
            "email": self.email,
            "created_at": self.created_at,
            "updated_at": self.updated_at
        }


# Customer input models
class CustomerCreate(BaseModel):
    first_name: str
    last_name: str
    email: Optional[str] = None


@router.get("/", response_model=List[dict])
async def get_customers():
    """Retrieve all customers"""
    try:
        db = get_db()
        customers = []
        
        for doc in db.collection("customers").stream():
            customer = Customer.from_dict(doc.id, doc.to_dict())
            customers.append(customer.to_dict())
        
        return customers
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error retrieving customers: {str(e)}")


@router.get("/{customer_id}", response_model=dict)
async def get_customer(customer_id: str):
    """Retrieve a specific customer by ID"""
    try:
        db = get_db()
        doc = db.collection("customers").document(customer_id).get()
        
        if not doc.exists:
            raise HTTPException(status_code=404, detail=f"Customer with ID {customer_id} not found")
        
        return Customer.from_dict(doc.id, doc.to_dict()).to_dict()
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error retrieving customer: {str(e)}")


@router.post("/", response_model=dict, status_code=201)
async def create_customer(customer: CustomerCreate = Body(...)):
    """Create a new customer"""
    try:
        db = get_db()
        
        customer_id = str(uuid.uuid4())
        now = datetime.now().isoformat()
        
        new_customer = Customer(
            id=customer_id,
            first_name=customer.first_name,
            last_name=customer.last_name,
            email=customer.email,
            created_at=now,
            updated_at=now
        )
        
        # Save to Firestore (excluding id from the stored document)
        db.collection("customers").document(customer_id).set(
            {k: v for k, v in new_customer.to_dict().items() if k != "id"}
        )
        
        return new_customer.to_dict()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error creating customer: {str(e)}")


@router.put("/{customer_id}", response_model=dict)
async def update_customer(customer_id: str, customer: CustomerCreate = Body(...)):
    """Update an existing customer"""
    try:
        db = get_db()
        doc_ref = db.collection("customers").document(customer_id)
        doc = doc_ref.get()
        
        if not doc.exists:
            raise HTTPException(status_code=404, detail=f"Customer with ID {customer_id} not found")
        
        # Update customer data
        updated_customer = Customer.from_dict(customer_id, doc.to_dict())
        updated_customer.first_name = customer.first_name
        updated_customer.last_name = customer.last_name
        updated_customer.email = customer.email
        updated_customer.updated_at = datetime.now().isoformat()
        
        # Save updates (excluding id)
        doc_ref.update({k: v for k, v in updated_customer.to_dict().items() if k != "id"})
        
        return updated_customer.to_dict()
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error updating customer: {str(e)}")


@router.delete("/{customer_id}", status_code=204)
async def delete_customer(customer_id: str):
    """Delete a customer"""
    try:
        db = get_db()
        doc_ref = db.collection("customers").document(customer_id)
        doc = doc_ref.get()
        
        if not doc.exists:
            raise HTTPException(status_code=404, detail=f"Customer with ID {customer_id} not found")
        
        doc_ref.delete()
        return None
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error deleting customer: {str(e)}") 
    

