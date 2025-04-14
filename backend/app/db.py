from firebase_admin import firestore, initialize_app, get_app, credentials
import os
import traceback

def get_db():
    """
    Get a Firestore client
    """
    try:
        print("========== DB INITIALIZATION DEBUG ==========")
        print("1. Checking if Firebase app is already initialized")
        
        # Try to get existing app
        try:
            app = get_app()
            print(f"2. Firebase app already initialized: {app}")
        except ValueError:
            print("3. No existing Firebase app found, initializing...")
            
            # Get the current environment
            env = os.environ.get("ENVIRONMENT", "dev")
            print(f"4. Current environment: {env}")
            
            # Prioritize checking for environment-specific Firebase credentials in secrets directory
            firebase_cred_path = f"secrets/firebase-admin-key-{env}.json"
            
            # For Cloud Run deployment, the path might be mounted at /secrets
            cloud_run_cred_path = f"/secrets/firebase-admin-key-{env}.json"
            
            if os.path.exists(firebase_cred_path):
                print(f"5. Found Firebase credentials at {firebase_cred_path}")
                try:
                    cred = credentials.Certificate(firebase_cred_path)
                    app = initialize_app(cred)
                    print("6. Firebase initialized with environment-specific service account credentials")
                except Exception as e:
                    print(f"Error initializing with service account: {e}")
                    print("Falling back to default credentials...")
                    app = initialize_app()
                    print("6. Firebase initialized with default configuration")
            elif os.path.exists(cloud_run_cred_path):
                print(f"5. Found Firebase credentials at {cloud_run_cred_path}")
                try:
                    cred = credentials.Certificate(cloud_run_cred_path)
                    app = initialize_app(cred)
                    print("6. Firebase initialized with environment-specific service account credentials (Cloud Run)")
                except Exception as e:
                    print(f"Error initializing with service account: {e}")
                    print("Falling back to default credentials...")
                    app = initialize_app()
                    print("6. Firebase initialized with default configuration")
            else:
                # Check for Application Default Credentials (ADC) path
                adc_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
                if adc_path and os.path.exists(adc_path):
                    print(f"5. Found Application Default Credentials at {adc_path}")
                    try:
                        cred = credentials.Certificate(adc_path)
                        app = initialize_app(cred)
                        print("6. Firebase initialized with ADC credentials")
                    except Exception as e:
                        print(f"Error initializing with ADC: {e}")
                        print("Falling back to default credentials...")
                        app = initialize_app()
                        print("6. Firebase initialized with default configuration")
                else:
                    # Initialize with default credentials
                    print("5. No explicit credentials found, using default")
                    app = initialize_app()
                    print("6. Firebase initialized with default configuration")
        
        print("7. Getting Firestore client")
        db = firestore.client()
        print(f"8. Firestore client obtained: {db}")
        print("========== END DB DEBUG ==========")
        return db
    except Exception as e:
        print(f"ERROR initializing Firestore: {str(e)}")
        traceback.print_exc()
        raise