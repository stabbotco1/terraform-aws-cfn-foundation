#!/bin/bash
# git-publish.sh - Squash all history to single commit and force push to remote
# This ensures the remote repository always has exactly one commit

set -euo pipefail

# Get current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Check if we're in a git repository
if [ -z "$CURRENT_BRANCH" ]; then
  echo "✗ Error: Not in a git repository"
  exit 1
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
  echo "✗ Error: You have uncommitted changes"
  echo "  Please commit or stash your changes first"
  exit 1
fi

# Check if remote exists
if ! git remote get-url origin &>/dev/null; then
  echo "✗ Error: No remote 'origin' configured"
  exit 1
fi

echo "=========================================="
echo "Git Publish - Squash and Push"
echo "=========================================="
echo "Current branch: $CURRENT_BRANCH"
echo ""
echo "Squashing all commits..."

# Create orphan branch with all current files
git checkout --orphan temp-publish-branch

# Add all files and create single commit
git add -A
git commit -m "initial commit"

# Replace current branch with squashed version
git branch -D "$CURRENT_BRANCH"
git branch -m "$CURRENT_BRANCH"

echo "✓ Squashed to single commit"
echo ""
echo "Force pushing to origin/$CURRENT_BRANCH..."

# Force push to remote
git push -f origin "$CURRENT_BRANCH"

echo ""
echo "=========================================="
echo "✓ Publish complete!"
echo "=========================================="
echo "Remote repository now has single commit: 'initial commit'"
