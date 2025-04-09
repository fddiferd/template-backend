#!/bin/bash
set -e

echo "Starting test verification process..."

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

# Check if Poetry is available
if command -v poetry &> /dev/null; then
    echo "Poetry found, using Poetry for dependency management..."
    poetry install
else
    echo "Poetry not found, using pip for dependency management..."
    # Use pip to install dependencies
    if [ -f "pyproject.toml" ]; then
        pip install -e .
    else
        echo "Error: pyproject.toml file not found"
        exit 1
    fi
fi

# Install missing dependencies if needed
if ! $PYTHON_CMD -c "import pytest" &> /dev/null; then
    echo "Pytest not found, installing..."
    if command -v poetry &> /dev/null; then
        poetry add pytest pytest-cov
    else
        pip install pytest pytest-cov
    fi
fi

if ! $PYTHON_CMD -c "import fastapi" &> /dev/null; then
    echo "FastAPI not found, installing..."
    if command -v poetry &> /dev/null; then
        poetry add fastapi uvicorn
    else
        pip install fastapi uvicorn
    fi
fi

if ! $PYTHON_CMD -c "import yaml" &> /dev/null; then
    echo "PyYAML not found, installing..."
    if command -v poetry &> /dev/null; then
        poetry add pyyaml
    else
        pip install pyyaml
    fi
fi

if ! $PYTHON_CMD -c "import httpx" &> /dev/null; then
    echo "httpx not found, installing..."
    if command -v poetry &> /dev/null; then
        poetry add httpx
    else
        pip install httpx
    fi
fi

# Run the tests using either Poetry or Python directly
echo "Running tests..."
if command -v poetry &> /dev/null; then
    echo "Running infrastructure tests..."
    poetry run pytest tests/test_infrastructure.py -v
    
    if [ $? -eq 0 ]; then
        echo "Running application tests..."
        poetry run pytest tests/test_app_exists.py -v
    else
        echo "Infrastructure tests failed. Exiting."
        exit 1
    fi
    
    if [ $? -eq 0 ]; then
        echo "Running CI/CD tests..."
        poetry run pytest tests/test_cicd.py -v
    else
        echo "Application tests failed. Exiting."
        exit 1
    fi
else
    echo "Running infrastructure tests..."
    $PYTHON_CMD -m pytest tests/test_infrastructure.py -v
    
    if [ $? -eq 0 ]; then
        echo "Running application tests..."
        $PYTHON_CMD -m pytest tests/test_app_exists.py -v
    else
        echo "Infrastructure tests failed. Exiting."
        exit 1
    fi
    
    if [ $? -eq 0 ]; then
        echo "Running CI/CD tests..."
        $PYTHON_CMD -m pytest tests/test_cicd.py -v
    else
        echo "Application tests failed. Exiting."
        exit 1
    fi
fi

# Check if all tests passed
if [ $? -eq 0 ]; then
    echo "All tests passed! Library verification complete."
    exit 0
else
    echo "Some tests failed. Please check the errors and fix them."
    exit 1
fi 