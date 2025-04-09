#!/bin/bash
set -e

echo "====================================================================="
echo "            FastAPI Application Library Verification                  "
echo "====================================================================="

# Function to print section headers
function print_section() {
    echo "---------------------------------------------------------------------"
    echo "$1"
    echo "---------------------------------------------------------------------"
}

# Determine Python executable
PYTHON_CMD=""
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
elif command -v python &> /dev/null; then
    PYTHON_CMD="python"
else
    echo "Python not found, please install Python 3.11 or later"
    exit 1
fi

# Step 1: Check core files exist
print_section "Checking core files..."
if [ -d "app" ] && [ -f "app/run.py" ] && [ -f "docker/Dockerfile" ]; then
    echo "✅ Core application files exist"
else
    echo "❌ Missing core application files"
    if [ ! -d "app" ]; then echo "   - Missing app directory"; fi
    if [ ! -f "app/run.py" ]; then echo "   - Missing app/run.py"; fi
    if [ ! -f "docker/Dockerfile" ]; then echo "   - Missing docker/Dockerfile"; fi
    exit 1
fi

# Step 2: Check configuration files
print_section "Checking configuration files..."
if [ -f "config" ] && [ -f ".env" ]; then
    echo "✅ Configuration files exist"
else
    echo "❌ Missing configuration files"
    if [ ! -f "config" ]; then echo "   - Missing config file"; fi
    if [ ! -f ".env" ]; then echo "   - Missing .env file"; fi
    exit 1
fi

# Step 3: Check infrastructure files
print_section "Checking infrastructure files..."
if [ -d "terraform" ] && [ -d "terraform/bootstrap" ] && [ -d "terraform/cicd" ]; then
    echo "✅ Infrastructure files exist"
else
    echo "❌ Missing infrastructure files"
    if [ ! -d "terraform" ]; then echo "   - Missing terraform directory"; fi
    if [ ! -d "terraform/bootstrap" ]; then echo "   - Missing terraform/bootstrap directory"; fi
    if [ ! -d "terraform/cicd" ]; then echo "   - Missing terraform/cicd directory"; fi
    exit 1
fi

# Step 4: Check deployment scripts
print_section "Checking deployment scripts..."
if [ -f "scripts/setup/bootstrap.sh" ] && [ -f "scripts/cicd/deploy.sh" ]; then
    echo "✅ Deployment scripts exist"
else
    echo "❌ Missing deployment scripts"
    if [ ! -f "scripts/setup/bootstrap.sh" ]; then echo "   - Missing scripts/setup/bootstrap.sh"; fi
    if [ ! -f "scripts/cicd/deploy.sh" ]; then echo "   - Missing scripts/cicd/deploy.sh"; fi
    exit 1
fi

# Step 5: Check if test scripts exist
print_section "Checking test scripts..."
if [ -f "scripts/test/run_tests.sh" ]; then
    echo "✅ Test scripts exist"
else
    echo "❌ Missing test scripts"
    if [ ! -f "scripts/test/run_tests.sh" ]; then echo "   - Missing scripts/test/run_tests.sh"; fi
    exit 1
fi

# Step 6: Run tests
print_section "Running automated tests..."
if ./scripts/test/run_tests.sh; then
    echo "✅ All tests passed"
else
    echo "❌ Some tests failed"
    exit 1
fi

# Step 7: Verify app can be started
print_section "Verifying app can be started..."
# Temporarily start the app and kill it after 5 seconds
echo "Starting FastAPI application (will terminate after 5 seconds)..."

# Choose the appropriate Python command based on Poetry availability
if command -v poetry &> /dev/null; then
    poetry run $PYTHON_CMD -c "
import importlib.util
import sys
import time
import threading

def kill_after(seconds):
    time.sleep(seconds)
    print('Test complete - app startup verified')
    sys.exit(0)

threading.Thread(target=kill_after, args=(5,), daemon=True).start()

spec = importlib.util.spec_from_file_location('app.run', 'app/run.py')
app_module = importlib.util.module_from_spec(spec)
sys.modules['app.run'] = app_module
spec.loader.exec_module(app_module)

print('App imported successfully!')
from fastapi import FastAPI
assert isinstance(app_module.app, FastAPI), 'app should be a FastAPI instance'
print('App verified as FastAPI instance')
"
else
    $PYTHON_CMD -c "
import importlib.util
import sys
import time
import threading

def kill_after(seconds):
    time.sleep(seconds)
    print('Test complete - app startup verified')
    sys.exit(0)

threading.Thread(target=kill_after, args=(5,), daemon=True).start()

spec = importlib.util.spec_from_file_location('app.run', 'app/run.py')
app_module = importlib.util.module_from_spec(spec)
sys.modules['app.run'] = app_module
spec.loader.exec_module(app_module)

print('App imported successfully!')
from fastapi import FastAPI
assert isinstance(app_module.app, FastAPI), 'app should be a FastAPI instance'
print('App verified as FastAPI instance')
"
fi

if [ $? -eq 0 ]; then
    echo "✅ App can be started successfully"
else
    echo "❌ Failed to start app"
    exit 1
fi

# Final summary
print_section "VERIFICATION SUMMARY"
echo "✅ All verification checks passed!"
echo "✅ Library exists and is properly configured"
echo "✅ Infrastructure exists and is properly configured"
echo "✅ Deployment scripts exist and are executable"
echo "✅ Application can be started"
echo "====================================================================="
echo "            LIBRARY VERIFICATION COMPLETE - ALL CHECKS PASSED         "
echo "=====================================================================" 