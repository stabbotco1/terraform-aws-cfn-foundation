#!/bin/bash
# scripts/verify-prerequisites.sh - Validate all prerequisites before deployment

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

FAILURES=()

echo "Verifying prerequisites for CloudFormation foundation deployment..."
echo ""

check_git_repo() {
  if git rev-parse --git-dir &>/dev/null; then
    echo -e "${GREEN}✓${NC} Inside git repository"
    return 0
  else
    echo -e "${RED}✗${NC} Not in a git repository"
    FAILURES+=("Not in git repository")
    return 1
  fi
}

check_git_uncommitted() {
  if git diff-index --quiet HEAD -- 2>/dev/null; then
    echo -e "${GREEN}✓${NC} No uncommitted changes"
    return 0
  else
    echo -e "${RED}✗${NC} Uncommitted changes detected"
    echo "  Commit or stash changes before deployment"
    FAILURES+=("Uncommitted changes")
    return 1
  fi
}

check_git_untracked() {
  if [ -z "$(git ls-files --others --exclude-standard)" ]; then
    echo -e "${GREEN}✓${NC} No untracked files"
    return 0
  else
    echo -e "${RED}✗${NC} Untracked files detected"
    echo "  Add or ignore untracked files before deployment"
    git ls-files --others --exclude-standard | sed 's/^/    /'
    FAILURES+=("Untracked files")
    return 1
  fi
}

check_git_detached_head() {
  if git symbolic-ref -q HEAD &>/dev/null; then
    echo -e "${GREEN}✓${NC} Not in detached HEAD state"
    return 0
  else
    echo -e "${RED}✗${NC} Detached HEAD state detected"
    echo "  Checkout a branch before deployment"
    FAILURES+=("Detached HEAD")
    return 1
  fi
}

check_git_upstream() {
  if git rev-parse --abbrev-ref @{u} &>/dev/null; then
    echo -e "${GREEN}✓${NC} Branch has upstream configured"
    return 0
  else
    echo -e "${RED}✗${NC} No upstream branch configured"
    echo "  Push branch and set upstream before deployment"
    FAILURES+=("No upstream branch")
    return 1
  fi
}

check_git_unpushed() {
  LOCAL=$(git rev-parse @ 2>/dev/null)
  REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "")
  
  if [ -z "$REMOTE" ]; then
    # Already caught by check_git_upstream
    return 0
  fi
  
  if [ "$LOCAL" = "$REMOTE" ]; then
    echo -e "${GREEN}✓${NC} No unpushed commits"
    return 0
  else
    echo -e "${RED}✗${NC} Unpushed commits detected"
    echo "  Push commits before deployment"
    FAILURES+=("Unpushed commits")
    return 1
  fi
}

check_aws_cli() {
  if command -v aws &>/dev/null; then
    AWS_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    echo -e "${GREEN}✓${NC} AWS CLI is installed (Version: $AWS_VERSION)"
    return 0
  else
    echo -e "${RED}✗${NC} AWS CLI not found"
    FAILURES+=("AWS CLI not installed")
    return 1
  fi
}

check_aws_auth() {
  if aws sts get-caller-identity &>/dev/null; then
    CALLER_ARN=$(aws sts get-caller-identity --query 'Arn' --output text)
    ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
    echo -e "${GREEN}✓${NC} AWS authentication valid"
    echo "  Account: $ACCOUNT_ID"
    echo "  Identity: $CALLER_ARN"
    return 0
  else
    echo -e "${RED}✗${NC} AWS authentication failed"
    echo "  Run: aws configure"
    FAILURES+=("AWS authentication")
    return 1
  fi
}

check_aws_permissions() {
  echo "Checking AWS permissions..."
  
  # Test CloudFormation permissions
  if aws cloudformation list-stacks --max-items 1 &>/dev/null; then
    echo -e "${GREEN}✓${NC} CloudFormation permissions valid"
  else
    echo -e "${RED}✗${NC} CloudFormation permissions insufficient"
    FAILURES+=("CloudFormation permissions")
  fi
  
  # Test IAM permissions
  if aws iam list-open-id-connect-providers &>/dev/null; then
    echo -e "${GREEN}✓${NC} IAM permissions valid"
  else
    echo -e "${RED}✗${NC} IAM permissions insufficient"
    FAILURES+=("IAM permissions")
  fi
  
  # Test S3 permissions
  if aws s3 ls &>/dev/null; then
    echo -e "${GREEN}✓${NC} S3 permissions valid"
  else
    echo -e "${RED}✗${NC} S3 permissions insufficient"
    FAILURES+=("S3 permissions")
  fi
  
  # Test DynamoDB permissions
  if aws dynamodb list-tables &>/dev/null; then
    echo -e "${GREEN}✓${NC} DynamoDB permissions valid"
  else
    echo -e "${RED}✗${NC} DynamoDB permissions insufficient"
    FAILURES+=("DynamoDB permissions")
  fi
  
  # Test SSM permissions
  if aws ssm describe-parameters --max-items 1 &>/dev/null; then
    echo -e "${GREEN}✓${NC} SSM Parameter Store permissions valid"
  else
    echo -e "${RED}✗${NC} SSM Parameter Store permissions insufficient"
    FAILURES+=("SSM permissions")
  fi
}

check_github_cli() {
  if command -v gh &>/dev/null; then
    GH_VERSION=$(gh --version | head -n1 | cut -d' ' -f3)
    echo -e "${GREEN}✓${NC} GitHub CLI is installed (Version: $GH_VERSION)"
    
    # Check authentication - now required
    if gh auth status &>/dev/null 2>&1; then
      GH_USER=$(gh api user --jq .login 2>/dev/null || echo "unknown")
      echo -e "${GREEN}✓${NC} GitHub CLI authenticated as: $GH_USER"
      return 0
    else
      echo -e "${RED}✗${NC} GitHub CLI not authenticated"
      echo "  Run: gh auth login"
      FAILURES+=("GitHub authentication required")
      return 1
    fi
  else
    echo -e "${RED}✗${NC} GitHub CLI not found"
    echo "  Install: https://cli.github.com/"
    FAILURES+=("GitHub CLI required")
    return 1
  fi
}

check_required_files() {
  if [ -f "bootstrap.yaml" ]; then
    echo -e "${GREEN}✓${NC} CloudFormation template found: bootstrap.yaml"
  else
    echo -e "${RED}✗${NC} Missing CloudFormation template: bootstrap.yaml"
    FAILURES+=("Missing bootstrap.yaml")
  fi
}

check_env_configuration() {
  # Check .env.example exists
  if [ ! -f ".env.example" ]; then
    echo -e "${RED}✗${NC} Missing .env.example template file"
    FAILURES+=("Missing .env.example")
    return 1
  fi
  
  # Check .env exists
  if [ ! -f ".env" ]; then
    echo -e "${RED}✗${NC} .env file missing"
    echo "  Copy .env.example to .env and update with your AWS account ID:"
    echo "  cp .env.example .env"
    echo "  # Edit .env with your actual AWS account ID"
    FAILURES+=(".env file missing")
    return 1
  fi
  
  # Check account ID isn't placeholder
  if grep -q "123456789012" .env; then
    echo -e "${RED}✗${NC} .env contains placeholder AWS_ACCOUNT_ID"
    echo "  Update AWS_ACCOUNT_ID in .env with your actual account ID"
    FAILURES+=("Placeholder AWS_ACCOUNT_ID in .env")
    return 1
  fi
  
  # Check account ID matches current AWS session
  CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo -e "${RED}✗${NC} Cannot get current AWS account ID"
    FAILURES+=("AWS authentication required for account ID check")
    return 1
  fi
  
  ENV_ACCOUNT=$(grep "^AWS_ACCOUNT_ID=" .env | cut -d'=' -f2 | tr -d ' ')
  if [ "$ENV_ACCOUNT" != "$CURRENT_ACCOUNT" ]; then
    echo -e "${RED}✗${NC} .env AWS_ACCOUNT_ID ($ENV_ACCOUNT) doesn't match current AWS session ($CURRENT_ACCOUNT)"
    echo "  Update AWS_ACCOUNT_ID in .env to match your current AWS account"
    FAILURES+=("AWS_ACCOUNT_ID mismatch")
    return 1
  fi
  
  echo -e "${GREEN}✓${NC} .env configuration valid (AWS_ACCOUNT_ID: $ENV_ACCOUNT)"
  return 0
}

check_target_repository() {
  # Load environment variables from config.env file
  if [ -f "config.env" ]; then
    export $(grep -v '^#' config.env | xargs)
  fi
  
  # Get repository URL and extract org
  REPOSITORY=$(git remote get-url origin | sed 's|git@github.com:|https://github.com/|')
  CURRENT_ORG=$(echo "$REPOSITORY" | sed -E 's|https://github.com/([^/]+)/.*|\1|')
  TARGET_REPO_NAME=${TARGET_DEPLOYMENT_ROLES_REPOSITORY:-"terraform-aws-deployment-roles"}
  TARGET_REPOSITORY="${CURRENT_ORG}/${TARGET_REPO_NAME}"
  
  echo "Checking target deployment roles repository..."
  echo "  Target: $TARGET_REPOSITORY"
  
  if gh repo view "$TARGET_REPOSITORY" &>/dev/null; then
    echo -e "${GREEN}✓${NC} Target repository exists and is accessible"
  else
    echo -e "${YELLOW}⚠${NC} Target repository does not exist: $TARGET_REPOSITORY"
    echo "  This is not a failure - the foundation can be deployed before the roles project"
    echo "  The deployment role will be created and ready when the target repository is created"
    echo "  See README.md for more information about the deployment roles integration"
  fi
}

check_openssl() {
  if command -v openssl &>/dev/null; then
    OPENSSL_VERSION=$(openssl version | cut -d' ' -f2)
    echo -e "${GREEN}✓${NC} openssl is installed (Version: $OPENSSL_VERSION)"
  else
    echo -e "${RED}✗${NC} openssl not found (required for GitLab OIDC thumbprint calculation)"
    echo "  Install: brew install openssl (macOS) or apt-get install openssl (Linux)"
    FAILURES+=("openssl required")
  fi
}

check_bash_version() {
  BASH_VERSION=${BASH_VERSION:-"unknown"}
  if [[ "$BASH_VERSION" =~ ^[4-9] ]]; then
    echo -e "${GREEN}✓${NC} Bash version compatible: $BASH_VERSION"
  else
    echo -e "${YELLOW}⚠${NC} Bash version may be incompatible: $BASH_VERSION"
    echo "  Recommended: Bash 4+ (macOS: brew install bash)"
  fi
}

check_jq() {
  if command -v jq &>/dev/null; then
    JQ_VERSION=$(jq --version)
    echo -e "${GREEN}✓${NC} jq is installed (Version: $JQ_VERSION)"
    return 0
  else
    echo -e "${RED}✗${NC} jq not found (required for bucket operations)"
    echo "  Install: brew install jq (macOS) or apt-get install jq (Linux)"
    FAILURES+=("jq required")
    return 1
  fi
}

# Run all checks
check_git_repo
check_git_uncommitted
check_git_untracked
check_git_detached_head
check_git_upstream
check_git_unpushed
check_bash_version
check_aws_cli
check_aws_auth
check_env_configuration
check_aws_permissions
check_github_cli
check_jq
check_openssl
check_required_files
check_target_repository

# Report results
echo ""
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo -e "${GREEN}✓ All prerequisites satisfied${NC}"
  echo ""
  exit 0
else
  echo -e "${RED}✗ Prerequisites check failed:${NC}"
  for failure in "${FAILURES[@]}"; do
    echo "  - $failure"
  done
  echo ""
  echo "Fix the above issues and try again."
  exit 1
fi