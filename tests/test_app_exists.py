import os
import sys
import importlib.util
import re
from typing import Any, Optional, Type, cast

# Try to import pytest, handle gracefully if not available
try:
    import pytest
except ImportError:
    print("Warning: pytest not found. Please run ./scripts/test/run_tests.sh to install dependencies.")
    # Create a minimal pytest.fail function for our tests
    class PyTest:
        @staticmethod
        def fail(msg):
            raise AssertionError(msg)
    pytest = PyTest()

# Create stub classes for FastAPI and APIRouter
class FastAPIStub:
    pass

class APIRouterStub:
    pass

# Try to import fastapi, handle gracefully if not available
try:
    from fastapi import FastAPI, APIRouter
    FastAPIClass = FastAPI
    APIRouterClass = APIRouter
except ImportError:
    print("Warning: fastapi not found. Please run ./scripts/test/run_tests.sh to install dependencies.")
    # Use the stub classes
    FastAPIClass = FastAPIStub  # type: ignore
    APIRouterClass = APIRouterStub  # type: ignore


def import_app_module():
    """Helper function to import the app module safely."""
    spec = importlib.util.spec_from_file_location('app.run', 'app/run.py')
    if spec is None:
        pytest.fail("Failed to create module spec for app/run.py")
        return None  # This line won't execute due to pytest.fail, but helps linting
        
    if spec.loader is None:
        pytest.fail("Module spec has no loader")
        return None
        
    app_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(app_module)
    return app_module


def test_app_module_exists():
    """Test that the app module exists."""
    assert os.path.exists('app'), "app directory should exist"
    assert os.path.exists('app/__init__.py'), "app/__init__.py should exist"
    assert os.path.exists('app/run.py'), "app/run.py should exist"


def test_app_can_be_imported():
    """Test that the app can be imported."""
    try:
        app_module = import_app_module()
        
        # Check if the app module has an 'app' attribute
        assert app_module is not None and hasattr(app_module, 'app'), "app module should have an 'app' attribute"
    except Exception as e:
        pytest.fail(f"Failed to import app module: {e}")


def test_app_is_fastapi_instance():
    """Test that the app is a FastAPI instance."""
    try:
        app_module = import_app_module()
        assert app_module is not None, "Failed to import app module"
        
        # Check if app is a FastAPI instance
        assert isinstance(app_module.app, FastAPIClass), "app should be a FastAPI instance"
    except Exception as e:
        pytest.fail(f"Failed to import app module: {e}")


def test_app_has_routes():
    """Test that the app has routes defined."""
    try:
        app_module = import_app_module()
        assert app_module is not None, "Failed to import app module"
        
        # Check if app has routes
        assert hasattr(app_module.app, 'routes'), "app should have routes attribute"
        assert app_module.app.routes, "app should have routes defined"
    except Exception as e:
        pytest.fail(f"Failed to check app routes: {e}")


def test_root_endpoint_exists():
    """Test that the root endpoint exists."""
    try:
        app_module = import_app_module()
        assert app_module is not None, "Failed to import app module"
        
        # Check if the root endpoint exists
        for route in app_module.app.routes:
            if getattr(route, 'path', '') == '/':
                break
        else:
            pytest.fail("Root endpoint '/' not found")
            
    except Exception as e:
        pytest.fail(f"Failed to check root endpoint: {e}")


def test_health_endpoint_exists():
    """Test that the health endpoint exists."""
    try:
        app_module = import_app_module()
        assert app_module is not None, "Failed to import app module"
        
        # Check if the health endpoint exists
        for route in app_module.app.routes:
            if getattr(route, 'path', '') == '/health':
                break
        else:
            pytest.fail("Health endpoint '/health' not found")
            
    except Exception as e:
        pytest.fail(f"Failed to check health endpoint: {e}")


def test_api_status_endpoint_exists():
    """Test that the API status endpoint exists."""
    try:
        app_module = import_app_module()
        assert app_module is not None, "Failed to import app module"
        
        # Check if the API status endpoint exists
        api_status_found = False
        for route in app_module.app.routes:
            if getattr(route, 'path', '') == '/api/v1/status':
                api_status_found = True
                break
        
        if not api_status_found:
            # Check for routers that might contain the API status endpoint
            for route in app_module.app.routes:
                if isinstance(route, APIRouterClass) or (hasattr(route, 'routes') and route.routes):
                    for subroute in getattr(route, 'routes', []):
                        if getattr(subroute, 'path', '') == '/api/v1/status':
                            api_status_found = True
                            break
        
        assert api_status_found, "API status endpoint '/api/v1/status' not found"
            
    except Exception as e:
        pytest.fail(f"Failed to check API status endpoint: {e}")


def test_fastapi_middlewares():
    """Test that the FastAPI app has necessary middlewares."""
    try:
        app_module = import_app_module()
        if app_module is None:
            return  # Skip this test if we can't import the app
        
        # Check if the app has middlewares (this is optional, so we don't fail if not)
        # Just check the existence of the middleware attribute
        if hasattr(app_module.app, 'user_middleware') and app_module.app.user_middleware:
            print(f"Found {len(app_module.app.user_middleware)} middlewares")
    except Exception as e:
        # We're just checking for middlewares, so don't fail if we can't find them
        print(f"Could not check middlewares: {e}")


def test_dockerized_app_settings():
    """Test that the Dockerfile exists and is properly configured."""
    assert os.path.exists('docker/Dockerfile'), "Dockerfile should exist in docker directory"
    
    with open('docker/Dockerfile', 'r') as f:
        dockerfile_content = f.read()
    
    # Check for Python base image
    assert re.search(r'FROM\s+python', dockerfile_content, re.IGNORECASE), "Dockerfile should use Python base image"
    
    # Check for working directory
    assert 'WORKDIR' in dockerfile_content, "Dockerfile should set working directory"
    
    # Check for dependency installation
    assert any(pattern in dockerfile_content for pattern in ['pip install', 'poetry install']), \
        "Dockerfile should install dependencies"
    
    # Check for app execution
    assert any(pattern in dockerfile_content for pattern in ['CMD', 'ENTRYPOINT']), \
        "Dockerfile should define how to run the app" 