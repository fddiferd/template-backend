# GCP Cloud Run FastAPI with Firebase Infrastructure

This Terraform configuration sets up the infrastructure for a FastAPI backend running on Google Cloud Run with Firebase/Firestore as the data store.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) installed (v0.14+)
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) installed
- A Google Cloud Platform project with billing enabled
- Docker image of your FastAPI application ready to deploy

## Configuration

Create a `terraform.tfvars` file with the following variables:

```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"
image      = "gcr.io/your-project-id/fastapi-app:latest"
```

## Usage

1. Initialize Terraform:

```bash
terraform init
```

2. Preview the changes:

```bash
terraform plan
```

3. Apply the configuration:

```bash
terraform apply
```

4. After deployment, the following outputs will be available:
   - The Cloud Run service URL
   - The Firestore database ID
   - Service account emails
   - Storage bucket URL

## FastAPI Application Configuration

Your FastAPI application should:

1. Load the Firebase credentials from `/secrets/firebase-credentials.json`
2. Connect to Firestore using the Firebase Admin SDK
3. Use the environment variable `FIREBASE_PROJECT_ID` to initialize Firebase

Example code for your FastAPI application:

```python
import os
import json
from fastapi import FastAPI
from firebase_admin import credentials, firestore, initialize_app

app = FastAPI()

# Initialize Firebase
cred_path = "/secrets/firebase-credentials.json"
cred = credentials.Certificate(cred_path)
firebase_app = initialize_app(cred)
db = firestore.client()

@app.get("/")
def read_root():
    return {"message": "FastAPI with Firebase is running!"}
```

## Clean Up

To destroy all resources:

```bash
terraform destroy
``` 