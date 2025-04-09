"""
Pytest configuration file.
This file helps pytest find the correct paths and provides shared fixtures.
"""
import os
import sys

# Add the project root to the Python path
# This allows imports from the root of the project
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))) 