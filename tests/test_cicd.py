import os
import json
import pytest
import subprocess
import yaml
import re

# Helper function to read config file
def get_project_details():
    """Get project details from config file."""
    try:
        project_id = None
        with open('config', 'r') as config_file:
            for line in config_file:
                if line.startswith('gcp_project_id'):
                    match = re.search(r"'([^']+)'", line)
                    if match:
                        project_id = match.group(1)
        
        # Read mode from .env
        mode = "dev"  # Default
        with open('.env', 'r') as env_file:
            for line in env_file:
                if line.startswith('MODE='):
                    mode = line.strip().split('=')[1]
        
        return {
            "project_id": project_id,
            "mode": mode
        }
    except Exception as e:
        pytest.fail(f"Failed to read project details: {e}")
        return None


def test_cloudbuild_file_exists():
    """Test that cloudbuild.yaml exists and is valid."""
    assert os.path.exists('scripts/cicd/cloudbuild.yaml'), "cloudbuild.yaml should exist in scripts/cicd/"
    
    try:
        with open('scripts/cicd/cloudbuild.yaml', 'r') as f:
            cloudbuild_config = yaml.safe_load(f)
            assert isinstance(cloudbuild_config, dict), "cloudbuild.yaml should be a valid YAML"
            assert 'steps' in cloudbuild_config, "cloudbuild.yaml should define steps"
            assert 'substitutions' in cloudbuild_config, "cloudbuild.yaml should define substitutions"
    except yaml.YAMLError:
        pytest.fail("cloudbuild.yaml is not valid YAML")
    except Exception as e:
        pytest.fail(f"Failed to parse cloudbuild.yaml: {e}")


def test_cicd_terraform_configuration():
    """Test that the Terraform CICD configuration includes trigger settings."""
    tf_path = 'terraform/cicd/main.tf'
    assert os.path.exists(tf_path), "terraform/cicd/main.tf should exist"
    
    with open(tf_path, 'r') as f:
        content = f.read()
        
        # Check for dev trigger configuration
        assert 'google_cloudbuild_trigger' in content, "CICD should configure Cloud Build triggers"
        assert 'dev_trigger' in content, "CICD should configure dev triggers"
        assert 'branch = "^(?!main$).*$"' in content, "Dev trigger should match non-main branches"
        
        # Check for staging trigger configuration (main branch)
        assert 'staging_trigger' in content, "CICD should configure staging triggers"
        assert 'branch = "main"' in content, "Staging trigger should match main branch"
        
        # Check for production trigger configuration (tags)
        assert 'prod_trigger' in content, "CICD should configure production triggers"
        assert 'tag = "^v.*$"' in content, "Production trigger should match tags starting with v"


def test_cicd_permissions():
    """Test that the CICD configuration includes necessary permissions."""
    tf_path = 'terraform/cicd/main.tf'
    assert os.path.exists(tf_path), "terraform/cicd/main.tf should exist"
    
    with open(tf_path, 'r') as f:
        content = f.read()
        
        # Check for Cloud Build permissions
        assert 'roles/run.admin' in content, "Cloud Build should have permission to deploy to Cloud Run"
        assert 'roles/storage.admin' in content, "Cloud Build should have storage admin permissions"
        assert 'roles/artifactregistry.writer' in content, "Cloud Build should have permission to write to Artifact Registry"


def test_branch_strategy():
    """Test that the repository has the expected branch structure."""
    try:
        # Get the list of branches (only works in a git repo)
        result = subprocess.run(['git', 'branch', '-a'], capture_output=True, text=True, check=True)
        branches = result.stdout
        
        # Look for main branch
        assert 'main' in branches or 'origin/main' in branches, "Repository should have a main branch"
        
    except subprocess.CalledProcessError:
        pytest.skip("Not in a git repository or git command failed - skipping branch check")
    except FileNotFoundError:
        pytest.skip("Git command not found - skipping branch check")


def test_environment_mapping():
    """Test that environment mapping to branches is properly configured."""
    project_details = get_project_details()
    if not project_details:
        pytest.skip("Could not read project details - skipping environment mapping check")

    # Check bootstrap.sh script for environment mapping logic
    assert os.path.exists('scripts/setup/bootstrap.sh'), "bootstrap.sh should exist in scripts/setup/"
    
    with open('scripts/setup/bootstrap.sh', 'r') as f:
        content = f.read()
        
        # Check for environment mapping logic
        assert 'if [ "$MODE" == "dev" ]' in content, "bootstrap.sh should handle dev environment"
        assert 'if [ "$MODE" == "staging" ]' in content, "bootstrap.sh should handle staging environment"
        assert 'if [ "$MODE" == "prod" ]' in content, "bootstrap.sh should handle prod environment"


def test_cicd_scripts():
    """Test that CI/CD scripts exist and are executable."""
    # Check bootstrap script
    assert os.path.exists('scripts/setup/bootstrap.sh'), "bootstrap.sh should exist in scripts/setup/"
    assert os.access('scripts/setup/bootstrap.sh', os.X_OK), "bootstrap.sh should be executable"
    
    # Check deployment script
    assert os.path.exists('scripts/cicd/deploy.sh'), "deploy.sh should exist in scripts/cicd/"
    assert os.access('scripts/cicd/deploy.sh', os.X_OK), "deploy.sh should be executable"


def test_docker_build_push_logic():
    """Test that the build and push steps are correctly defined in the cloudbuild.yaml."""
    assert os.path.exists('scripts/cicd/cloudbuild.yaml'), "cloudbuild.yaml should exist in scripts/cicd/"
    
    with open('scripts/cicd/cloudbuild.yaml', 'r') as f:
        try:
            cloudbuild_config = yaml.safe_load(f)
            steps = cloudbuild_config.get('steps', [])
            
            # Check for build step
            build_steps = [step for step in steps if 'build' in str(step)]
            assert len(build_steps) > 0, "cloudbuild.yaml should include a build step"
            
            # Check for push step
            push_steps = [step for step in steps if 'push' in str(step)]
            assert len(push_steps) > 0, "cloudbuild.yaml should include a push step"
            
            # Check for deploy step
            deploy_steps = [step for step in steps if 'deploy' in str(step)]
            assert len(deploy_steps) > 0, "cloudbuild.yaml should include a deploy step"
        
        except yaml.YAMLError:
            pytest.fail("cloudbuild.yaml is not valid YAML")
        except Exception as e:
            pytest.fail(f"Failed to parse cloudbuild.yaml: {e}")


if __name__ == "__main__":
    pytest.main(["-v", __file__]) 