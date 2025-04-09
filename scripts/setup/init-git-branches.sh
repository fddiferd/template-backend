#!/bin/bash

# Get the current branch
CURRENT_BRANCH=$(git branch --show-current)

echo "Current branch: $CURRENT_BRANCH"
echo "Creating branches for deployment testing..."

# Create dev branch if it doesn't exist
if ! git show-ref --quiet refs/heads/dev; then
  echo "Creating dev branch..."
  git branch dev
else
  echo "Dev branch already exists"
fi

# Create staging branch if it doesn't exist
if ! git show-ref --quiet refs/heads/staging; then
  echo "Creating staging branch..."
  git branch staging
else
  echo "Staging branch already exists"
fi

# Create master branch if it doesn't exist
if ! git show-ref --quiet refs/heads/master; then
  echo "Creating master branch..."
  git branch master
else
  echo "Master branch already exists"
fi

echo "Branches created:"
git branch

echo ""
echo "To test deployments, use the following commands:"
echo ""
echo "Dev deployment:"
echo "  git checkout dev"
echo "  git add ."
echo "  git commit -m 'Test dev deployment'"
echo "  git push origin dev"
echo ""
echo "Staging deployment:"
echo "  git checkout staging"
echo "  git add ."
echo "  git commit -m 'Test staging deployment'"
echo "  git push origin staging"
echo ""
echo "Production deployment:"
echo "  git checkout master"
echo "  git add ."
echo "  git commit -m 'Test production deployment'"
echo "  git push origin master"
echo ""
echo "To return to your original branch:"
echo "  git checkout $CURRENT_BRANCH" 