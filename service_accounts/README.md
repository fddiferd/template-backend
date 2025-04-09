# Firebase Service Accounts

This directory contains Firebase service account key files needed for Firebase integration.

## Required Files

- `firebase-dev.json` - Development environment credentials
- `firebase-staging.json` - Staging environment credentials  
- `firebase-prod.json` - Production environment credentials

## How to Get Firebase Service Account Keys

1. Go to the Firebase Console: https://console.firebase.google.com/
2. Select your project
3. Navigate to Project Settings > Service accounts
4. Click on "Generate new private key" button
5. Save the JSON file and rename it to match the environment (e.g., `firebase-dev.json`)
6. Place the file in this directory

Note: These files contain sensitive credentials and should never be committed to version control.
The `.gitignore` file is configured to exclude these JSON files. 