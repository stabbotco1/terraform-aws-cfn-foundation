#!/bin/bash
# scripts/verify-prerequisites.sh - Validate all prerequisites before deployment

set -euo pipefail

FAILURES=()

echo "Verifying prerequisites for CloudFormation foundation deployment..."
echo ""

check_aws_cli() {
  if command -v aws &>/dev/null; then
    echo "✓ AWS CLI is installed"
    AWS_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    echo "  Version: $AWS_VERSION"
    return 0
  else
    echo "✗ AWS CLI not found"
    FAILURES+=("AWS CLI not installed")
    return 1
  fi
}

check_aws_auth() {
  if aws sts get-caller-identity &>/dev/null; then
    CALLER_ARN=$(aws sts get-caller-identity --query 'Arn' --output text)
    ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
    echo "✓ AWS authentication valid"
    echo "  Account: $ACCOUNT_ID"
    echo "  Identity: $CALLER_ARN"
    return 0
  else
    echo "✗ AWS authentication failed"
    echo "  Run: aws configure"
    FAILURES+=("AWS authentication")
    return 1
  fi
}

check_aws_permissions() {
  echo "Checking AWS permissions..."
  
  # Test CloudFormation permissions
  if aws cloudformation list-stacks --max-items 1 &>/dev/null; then
    echo "✓ CloudFormation permissions valid"
  else
    echo "✗ CloudFormation permissions insufficient"
    FAILURES+=("CloudFormation permissions")
  fi
  
  # Test IAM permissions
  if aws iam list-open-id-connect-providers &>/dev/null; then
    echo "✓ IAM permissions valid"
  else
    echo "✗ IAM permissions insufficient"
    FAILURES+=("IAM permissions")
  fi
  
  # Test S3 permissions
  if aws s3 ls &>/dev/null; then
    echo "✓ S3 permissions valid"
  else
    echo "✗ S3 permissions insufficient"
    FAILURES+=("S3 permissions")
  fi
  
  # Test DynamoDB permissions
  if aws dynamodb list-tables &>/dev/null; then
    echo "✓ DynamoDB permissions valid"
  else
    echo "✗ DynamoDB permissions insufficient"
    FAILURES+=("DynamoDB permissions")
  fi
  
  # Test SSM permissions
  if aws ssm describe-parameters --max-items 1 &>/dev/null; then
    echo "✓ SSM Parameter Store permissions valid"
  else
    echo "✗ SSM Parameter Store permissions insufficient"
    FAILURES+=("SSM permissions")
  fi
}

check_github_cli() {
  if command -v gh &>/dev/null; then
    echo "✓ GitHub CLI is installed"
    GH_VERSION=$(gh --version | head -n1 | cut -d' ' -f3)
    echo "  Version: $GH_VERSION"
    
    # Check authentication - now required
    if gh auth status &>/dev/null 2>&1; then
      GH_USER=$(gh api user --jq .login 2>/dev/null || echo "unknown")
      echo "✓ GitHub CLI authenticated as: $GH_USER"
      return 0
    else
      echo "✗ GitHub CLI not authenticated"
      echo "  Run: gh auth login"
      FAILURES+=("GitHub authentication required")
      return 1
    fi
  else
    echo "✗ GitHub CLI not found"
    echo "  Install: https://cli.github.com/"
    FAILURES+=("GitHub CLI required")
    return 1
  fi
}

check_required_files() {
  if [ -f "bootstrap.yaml" ]; then
    echo "✓ CloudFormation template found: bootstrap.yaml"
  else
    echo "✗ Missing CloudFormation template: bootstrap.yaml"
    FAILURES+=("Missing bootstrap.yaml")
  fi
}

check_bash_version() {
  BASH_VERSION=${BASH_VERSION:-"unknown"}
  if [[ "$BASH_VERSION" =~ ^[4-9] ]]; then
    echo "✓ Bash version compatible: $BASH_VERSION"
  else
    echo "⚠ Bash version may be incompatible: $BASH_VERSION"
    echo "  Recommended: Bash 4+ (macOS: brew install bash)"
  fi
}

check_jq() {
  if command -v jq &>/dev/null; then
    echo "✓ jq is installed"
    JQ_VERSION=$(jq --version)
    echo "  Version: $JQ_VERSION"
  else
    echo "⚠ jq not found (recommended for scripts)"
    echo "  Install: brew install jq (macOS) or apt-get install jq (Linux)"
  fi
}

# Run all checks
check_bash_version
check_aws_cli
check_aws_auth
check_aws_permissions
check_github_cli
check_jq
check_required_files

# Report results
echo ""
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "✓ All critical prerequisites satisfied"
  echo ""
  echo "Ready to deploy CloudFormation foundation!"
  exit 0
else
  echo "✗ Prerequisites check failed:"
  for failure in "${FAILURES[@]}"; do
    echo "  - $failure"
  done
  echo ""
  echo "Fix the above issues and try again."
  exit 1
fi