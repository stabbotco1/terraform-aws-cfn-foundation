#!/bin/bash
# Release script - squashes git history and creates version tag

set -euo pipefail

VERSION=$1

if [ -z "$VERSION" ]; then
  echo "Usage: ./scripts/release-version.sh <version>"
  echo "Example: ./scripts/release-version.sh v1.0.0"
  exit 1
fi

# Validate version format
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "✗ Invalid version format: $VERSION"
  echo "  Expected format: vMAJOR.MINOR.PATCH (e.g., v1.0.0)"
  exit 1
fi

# Check if tag already exists
if git rev-parse "$VERSION" >/dev/null 2>&1; then
  echo "✗ Tag $VERSION already exists"
  exit 1
fi

# Confirm action
echo "This will:"
echo "  1. Squash all git history into a single commit"
echo "  2. Create tag: $VERSION"
echo "  3. Force push to origin"
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
  echo "Release cancelled"
  exit 0
fi

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)

# Squash history
echo "Squashing git history..."
git checkout --orphan new-main
git add -A
git commit -m "Release $VERSION"
git branch -D "$CURRENT_BRANCH"
git branch -m "$CURRENT_BRANCH"

# Create tag
echo "Creating tag $VERSION..."
git tag "$VERSION"

echo ""
echo "✓ Release prepared: $VERSION"
echo ""
echo "To push to remote:"
echo "  git push -f origin $CURRENT_BRANCH"
echo "  git push origin $VERSION"
