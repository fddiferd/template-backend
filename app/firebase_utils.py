import os
import logging
import json
from typing import Dict, Any, Optional, List, Union, cast, TypeVar

# Define a type variable for the Client to help with type checking
FirestoreClientType = TypeVar('FirestoreClientType')

# Import Firestore
try:
    import firebase_admin
    from firebase_admin import credentials, firestore
    # Import but don't use directly in type annotations
    from google.cloud.firestore_v1.client import Client 
    from google.cloud.firestore_v1.collection import CollectionReference
    FIREBASE_IMPORTS_AVAILABLE = True
except ImportError:
    FIREBASE_IMPORTS_AVAILABLE = False
    # No need for stub classes as we use Any for type checking

logger = logging.getLogger(__name__)

# Firebase credentials path from environment variable
FIREBASE_CRED_PATH = os.getenv("FIREBASE_CRED_PATH", "service_accounts/firebase-dev.json")

def initialize_firebase() -> Optional[Any]:
    """Initialize Firebase connection using service account credentials"""
    try:
        if not FIREBASE_IMPORTS_AVAILABLE:
            logger.error("Firebase dependencies not available")
            return None
            
        # Check if credentials file exists
        if not os.path.exists(FIREBASE_CRED_PATH):
            logger.error(f"Firebase credentials file not found at {FIREBASE_CRED_PATH}")
            logger.error("Please run the bootstrap script to set up Firebase credentials")
            return None
        
        # Check if already initialized
        if not firebase_admin._apps:
            # Initialize the Firebase app
            cred = credentials.Certificate(FIREBASE_CRED_PATH)
            firebase_admin.initialize_app(cred)
            logger.info(f"Firebase initialized with credentials from {FIREBASE_CRED_PATH}")
        
        # Return Firestore client
        return firestore.client()
    except Exception as e:
        logger.error(f"Error initializing Firebase: {e}")
        return None

def create_customer(customer_data: Dict[str, Any]) -> Optional[str]:
    """
    Create a new customer in Firestore
    
    Args:
        customer_data: Dictionary containing customer information
        
    Returns:
        Optional[str]: Customer ID if successful, None otherwise
    """
    try:
        db = initialize_firebase()
        if not db:
            return None
        
        # Add customer to Firestore
        customers_ref = db.collection('customers')
        customer_ref = customers_ref.add(customer_data)
        return customer_ref[1].id
    except Exception as e:
        logger.error(f"Error creating customer: {e}")
        return None

def get_customer(customer_id: str) -> Optional[Dict[str, Any]]:
    """
    Get a customer by ID from Firestore
    
    Args:
        customer_id: The ID of the customer to retrieve
        
    Returns:
        Optional[Dict[str, Any]]: Customer data if found, None otherwise
    """
    try:
        db = initialize_firebase()
        if not db:
            return None
        
        customer_ref = db.collection('customers').document(customer_id)
        customer = customer_ref.get()
        if customer.exists:
            return customer.to_dict()
        else:
            logger.warning(f"Customer with ID {customer_id} not found in Firestore")
            return None
    except Exception as e:
        logger.error(f"Error retrieving customer: {e}")
        return None

def update_customer(customer_id: str, customer_data: Dict[str, Any]) -> bool:
    """
    Update a customer in Firestore
    
    Args:
        customer_id: The ID of the customer to update
        customer_data: The new customer data
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        db = initialize_firebase()
        if not db:
            return False
            
        customer_ref = db.collection('customers').document(customer_id)
        customer_ref.update(customer_data)
        return True
    except Exception as e:
        logger.error(f"Error updating customer: {e}")
        return False

def delete_customer(customer_id: str) -> bool:
    """
    Delete a customer from Firestore
    
    Args:
        customer_id: The ID of the customer to delete
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        db = initialize_firebase()
        if not db:
            return False
            
        customer_ref = db.collection('customers').document(customer_id)
        customer_ref.delete()
        return True
    except Exception as e:
        logger.error(f"Error deleting customer: {e}")
        return False

def list_customers(limit: int = 100) -> List[Dict[str, Any]]:
    """
    List all customers from Firestore
    
    Args:
        limit: Maximum number of customers to return
        
    Returns:
        List[Dict[str, Any]]: List of customers
    """
    try:
        db = initialize_firebase()
        if not db:
            return []
            
        customers_ref = db.collection('customers').limit(limit)
        customers = customers_ref.stream()
        
        # Convert to list of dictionaries
        result = []
        for customer in customers:
            customer_data = customer.to_dict()
            customer_data['id'] = customer.id
            result.append(customer_data)
            
        return result
    except Exception as e:
        logger.error(f"Error listing customers: {e}")
        return [] 