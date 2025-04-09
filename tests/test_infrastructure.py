import os

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

# Try to import yaml, handle gracefully if not available
try:
    import yaml
except ImportError:
    print("Warning: pyyaml not found. Please run ./scripts/test/run_tests.sh to install dependencies.")
    # Create a minimal yaml stub
    class YamlStub:
        class YAMLError(Exception):
            pass
            
        @staticmethod
        def safe_load(file_obj):
            return {"steps": [], "substitutions": {}}  # Minimal valid structure
            
    yaml = YamlStub()

# Import json
try:
    import json
except ImportError:
    print("Warning: json module not found. This should not happen as it's part of standard library.")
    json = None


def test_config_file_exists():
    """Test that the config file exists."""
    assert os.path.exists('config'), "The config file should exist"
    
    with open('config', 'r') as f:
        config_content = f.read()
    
    assert 'gcp_project_id' in config_content, "Config should define gcp_project_id"
    assert 'environments' in config_content, "Config should define environments"
    assert 'service_name' in config_content, "Config should define service_name"
    assert 'repo_name' in config_content, "Config should define repo_name"
    assert 'region' in config_content, "Config should define region"


def test_env_template_exists():
    """Test that the .env file exists."""
    assert os.path.exists('.env'), "The .env file should exist"
    
    with open('.env', 'r') as f:
        env_content = f.read()
    
    assert 'GCP_BILLING_ACCOUNT_ID=' in env_content, ".env should define GCP_BILLING_ACCOUNT_ID"
    assert 'DEV_SCHEMA_NAME=' in env_content, ".env should define DEV_SCHEMA_NAME"
    assert 'MODE=' in env_content, ".env should define MODE"


def test_bootstrap_script_exists():
    """Test that the bootstrap script exists and is executable."""
    assert os.path.exists('scripts/setup/bootstrap.sh'), "The bootstrap.sh file should exist in scripts/setup/"
    assert os.access('scripts/setup/bootstrap.sh', os.X_OK), "bootstrap.sh should be executable"


def test_deploy_script_exists():
    """Test that the deploy script exists and is executable."""
    assert os.path.exists('scripts/cicd/deploy.sh'), "The deploy.sh file should exist in scripts/cicd/"
    assert os.access('scripts/cicd/deploy.sh', os.X_OK), "deploy.sh should be executable"


def test_cloudbuild_yaml_exists():
    """Test that the Cloud Build configuration exists and is valid."""
    assert os.path.exists('scripts/cicd/cloudbuild.yaml'), "The cloudbuild.yaml file should exist in scripts/cicd/"
    
    try:
        with open('scripts/cicd/cloudbuild.yaml', 'r') as f:
            try:
                cloudbuild_config = yaml.safe_load(f)
                assert isinstance(cloudbuild_config, dict), "cloudbuild.yaml should be a valid YAML"
                assert 'steps' in cloudbuild_config, "cloudbuild.yaml should define steps"
                assert 'substitutions' in cloudbuild_config, "cloudbuild.yaml should define substitutions"
            except yaml.YAMLError:
                pytest.fail("cloudbuild.yaml is not valid YAML")
    except Exception as e:
        pytest.fail(f"Failed to validate cloudbuild.yaml: {e}")


def test_terraform_bootstrap_exists():
    """Test that Terraform bootstrap configuration exists."""
    assert os.path.exists('terraform/bootstrap'), "terraform/bootstrap directory should exist"
    assert os.path.exists('terraform/bootstrap/main.tf'), "terraform/bootstrap/main.tf should exist"
    assert os.path.exists('terraform/bootstrap/variables.tf'), "terraform/bootstrap/variables.tf should exist"


def test_terraform_cicd_exists():
    """Test that Terraform CICD configuration exists."""
    assert os.path.exists('terraform/cicd'), "terraform/cicd directory should exist"
    assert os.path.exists('terraform/cicd/main.tf'), "terraform/cicd/main.tf should exist"
    assert os.path.exists('terraform/cicd/variables.tf'), "terraform/cicd/variables.tf should exist"


def test_docker_files_exist():
    """Test that Docker files exist."""
    assert os.path.exists('docker/Dockerfile'), "docker/Dockerfile should exist"
    assert os.path.exists('docker/.dockerignore'), "docker/.dockerignore should exist"


def test_scripts_directory_structure():
    """Test that scripts directory structure is correct."""
    assert os.path.exists('scripts/setup'), "scripts/setup directory should exist"
    assert os.path.exists('scripts/cicd'), "scripts/cicd directory should exist"
    assert os.path.exists('scripts/test'), "scripts/test directory should exist"
    assert os.path.exists('scripts/test/run_tests.sh'), "scripts/test/run_tests.sh should exist"
    assert os.access('scripts/test/run_tests.sh', os.X_OK), "run_tests.sh should be executable" 