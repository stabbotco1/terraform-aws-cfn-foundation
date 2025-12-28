#!/bin/bash
# scripts/destroy.sh - Destroy CloudFormation foundation and all resources

set -euo pipefail

# Disable AWS CLI pager
export AWS_PAGER=""

# Extract stack name from repository name
STACK_NAME=$(git remote get-url origin | sed -E 's|.*/([^/]+)\.git$|\1|')

# Verify prerequisites (includes git state checks)
echo "Verifying prerequisites..."
./scripts/verify-prerequisites.sh || exit 1

echo ""

# Function to safely delete a versioned S3 bucket
delete_versioned_bucket() {
  local bucket=$1

  if ! aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
    return 0  # Bucket doesn't exist, nothing to do
  fi

  echo "  Emptying bucket: $bucket"

  # Delete all object versions using jq
  aws s3api list-object-versions \
    --bucket "$bucket" \
    --output json \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' 2>/dev/null | \
  jq -r '.Objects[]? | @json' | \
  while IFS= read -r obj; do
    KEY=$(echo "$obj" | jq -r '.Key')
    VERSION_ID=$(echo "$obj" | jq -r '.VersionId')
    aws s3api delete-object --bucket "$bucket" --key "$KEY" --version-id "$VERSION_ID" &>/dev/null || true
  done

  # Delete all delete markers
  aws s3api list-object-versions \
    --bucket "$bucket" \
    --output json \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' 2>/dev/null | \
  jq -r '.Objects[]? | @json' | \
  while IFS= read -r obj; do
    KEY=$(echo "$obj" | jq -r '.Key')
    VERSION_ID=$(echo "$obj" | jq -r '.VersionId')
    aws s3api delete-object --bucket "$bucket" --key "$KEY" --version-id "$VERSION_ID" &>/dev/null || true
  done

  # Final cleanup and delete
  aws s3 rm "s3://$bucket" --recursive &>/dev/null || true
  aws s3api delete-bucket --bucket "$bucket" 2>/dev/null && echo "  ✓ Deleted bucket: $bucket" || echo "  ⚠ Failed to delete bucket: $bucket"
}

# Get AWS account info
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=${AWS_REGION:-$(aws configure get region || echo "us-east-1")}
STATE_BUCKET="terraform-state-${ACCOUNT_ID}-${REGION}"
LOG_BUCKET="terraform-state-logs-${ACCOUNT_ID}-${REGION}"

# Check if stack exists
STACK_EXISTS=false
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
  STACK_EXISTS=true
fi

# Check for orphaned buckets
ORPHANED_BUCKETS=false
if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null || aws s3api head-bucket --bucket "$LOG_BUCKET" 2>/dev/null; then
  ORPHANED_BUCKETS=true
fi

# If nothing exists, exit early
if [ "$STACK_EXISTS" = false ] && [ "$ORPHANED_BUCKETS" = false ]; then
  echo "ℹ Stack '$STACK_NAME' does not exist"
  echo "ℹ No orphaned buckets found"
  echo ""
  echo "✓ No resources to destroy"
  exit 0
fi

# Show what will be destroyed
echo "=========================================="
echo "TERRAFORM FOUNDATION DESTRUCTION"
echo "=========================================="
echo ""
echo "⚠️  WARNING: This will permanently delete:"

if [ "$STACK_EXISTS" = true ]; then
  echo "  - CloudFormation stack: $STACK_NAME"
  echo "  - DynamoDB lock table (always deleted)"
  echo "  - All SSM parameters"
fi

if [ "$ORPHANED_BUCKETS" = true ]; then
  echo "  - Orphaned S3 buckets (optional - see next prompt)"
elif [ "$STACK_EXISTS" = true ]; then
  echo "  - S3 buckets (optional - see next prompt)"
fi

echo ""
echo "This action is IRREVERSIBLE."
echo ""

# Require DESTROY confirmation
read -p "Type 'DESTROY' to confirm: " confirmation

if [ "$confirmation" != "DESTROY" ]; then
  echo "Destruction cancelled"
  exit 0
fi

# Ask about S3 buckets if they exist or might exist
echo ""
echo "S3 buckets contain Terraform state and are protected by default."
echo "⚠️  Deleting buckets will permanently destroy all state history."
echo ""
read -p "Type 'DELETE BUCKETS' to destroy buckets (or press Enter to retain): " bucket_confirm

if [ "$bucket_confirm" = "DELETE BUCKETS" ]; then
  DESTROY_BUCKETS=true
  echo "✓ Buckets will be destroyed"
else
  DESTROY_BUCKETS=false
  echo "✓ Buckets will be retained"
fi

echo ""
echo "Starting destruction process..."
echo ""

# Handle case where only orphaned buckets exist (no stack)
if [ "$STACK_EXISTS" = false ]; then
  echo "ℹ Stack '$STACK_NAME' does not exist"

  if [ "$DESTROY_BUCKETS" = true ] && [ "$ORPHANED_BUCKETS" = true ]; then
    echo ""
    echo "Cleaning up orphaned buckets..."

    if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
      echo "  Found orphaned state bucket: $STATE_BUCKET"
      delete_versioned_bucket "$STATE_BUCKET"
    fi

    if aws s3api head-bucket --bucket "$LOG_BUCKET" 2>/dev/null; then
      echo "  Found orphaned log bucket: $LOG_BUCKET"
      delete_versioned_bucket "$LOG_BUCKET"
    fi

    echo ""
    echo "=========================================="
    echo "✓ DESTRUCTION COMPLETE"
    echo "=========================================="
    echo ""
    echo "Orphaned buckets have been destroyed."
  else
    echo ""
    echo "✓ Orphaned buckets retained"
  fi

  exit 0
fi

# Check stack status
STACK_STATUS=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].StackStatus' \
  --output text 2>/dev/null || echo "UNKNOWN")

case "$STACK_STATUS" in
  *_IN_PROGRESS)
    echo "✗ Stack operation in progress: $STACK_STATUS"
    echo "  Please wait for the current operation to complete and try again"
    exit 1
    ;;
  ROLLBACK_COMPLETE)
    echo "ℹ Stack is in ROLLBACK_COMPLETE state"
    echo "  This is a failed stack that can be deleted directly"
    ;;
  DELETE_FAILED)
    echo "⚠ Stack is in DELETE_FAILED state"
    echo "  Will attempt to complete deletion"
    echo "  Note: Some resources may require manual cleanup"
    ;;
  *)
    echo "ℹ Stack status: $STACK_STATUS"
    ;;
esac

# Get stack resources
echo "Step 1: Retrieving stack resources..."
RESOURCES=$(aws cloudformation describe-stack-resources --stack-name "$STACK_NAME" --output json)

# Extract resource information
STATE_BUCKET=$(echo "$RESOURCES" | jq -r '.StackResources[] | select(.ResourceType=="AWS::S3::Bucket" and .LogicalResourceId=="TerraformStateBucket") | .PhysicalResourceId' 2>/dev/null || echo "")
LOG_BUCKET=$(echo "$RESOURCES" | jq -r '.StackResources[] | select(.ResourceType=="AWS::S3::Bucket" and .LogicalResourceId=="TerraformStateLogBucket") | .PhysicalResourceId' 2>/dev/null || echo "")
DYNAMODB_TABLE=$(echo "$RESOURCES" | jq -r '.StackResources[] | select(.ResourceType=="AWS::DynamoDB::Table") | .PhysicalResourceId' 2>/dev/null || echo "")

echo "Resources to destroy:"
[ -n "$STATE_BUCKET" ] && echo "  - S3 State Bucket: $STATE_BUCKET $([ "$DESTROY_BUCKETS" = true ] && echo '(will delete)' || echo '(will retain)')"
[ -n "$LOG_BUCKET" ] && echo "  - S3 Log Bucket: $LOG_BUCKET $([ "$DESTROY_BUCKETS" = true ] && echo '(will delete)' || echo '(will retain)')"
[ -n "$DYNAMODB_TABLE" ] && echo "  - DynamoDB Table: $DYNAMODB_TABLE (will delete)"
echo ""

# Step 2: Disable stack termination protection
echo "Step 2: Disabling stack termination protection..."
aws cloudformation update-termination-protection \
  --stack-name "$STACK_NAME" \
  --no-enable-termination-protection &>/dev/null || true
echo "✓ Termination protection disabled"
echo ""

# Step 3: Disable DynamoDB deletion protection
if [ -n "$DYNAMODB_TABLE" ]; then
  echo "Step 3: Disabling DynamoDB deletion protection..."
  aws dynamodb update-table \
    --table-name "$DYNAMODB_TABLE" \
    --no-deletion-protection-enabled &>/dev/null || true
  echo "✓ DynamoDB deletion protection disabled"
  echo ""
fi

# Step 4: Empty S3 buckets if requested
if [ "$DESTROY_BUCKETS" = true ]; then
  echo "Step 4: Emptying S3 buckets..."

  if [ -n "$STATE_BUCKET" ]; then
    delete_versioned_bucket "$STATE_BUCKET"
  fi

  if [ -n "$LOG_BUCKET" ]; then
    delete_versioned_bucket "$LOG_BUCKET"
  fi

  echo "✓ Buckets emptied"
  echo ""
fi

# Step 5: Delete CloudFormation stack
echo "Step 5: Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name "$STACK_NAME"
echo "  Waiting for stack deletion to complete..."

if aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" 2>&1; then
  echo "✓ Stack deleted successfully"
else
  # Check what actually happened
  FINAL_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
    --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DELETED")

  case "$FINAL_STATUS" in
    DELETED)
      echo "✓ Stack deleted successfully"
      ;;
    DELETE_FAILED)
      echo "⚠ Stack deletion failed with status: DELETE_FAILED"
      echo ""
      echo "  Failed resources:"
      aws cloudformation describe-stack-resources --stack-name "$STACK_NAME" \
        --query 'StackResources[?ResourceStatus==`DELETE_FAILED`].[LogicalResourceId,ResourceType,ResourceStatusReason]' \
        --output table 2>/dev/null || true
      echo ""
      echo "  You may need to manually delete these resources and retry"
      exit 1
      ;;
    *)
      echo "⚠ Unexpected status: $FINAL_STATUS"
      exit 1
      ;;
  esac
fi
echo ""

# Step 6: Clean up remaining S3 buckets if requested (only if not managed by stack)
if [ "$DESTROY_BUCKETS" = true ]; then
  echo "Step 6: Verifying S3 bucket cleanup..."

  CLEANED_BUCKETS=false

  if [ -n "$STATE_BUCKET" ] && aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
    echo "  State bucket still exists (retained by DeletionPolicy), deleting..."
    aws s3api delete-bucket --bucket "$STATE_BUCKET" 2>/dev/null && {
      echo "  ✓ State bucket deleted"
      CLEANED_BUCKETS=true
    } || echo "  ⚠ Failed to delete state bucket (may already be deleted)"
  fi

  if [ -n "$LOG_BUCKET" ] && aws s3api head-bucket --bucket "$LOG_BUCKET" 2>/dev/null; then
    echo "  Log bucket still exists (retained by DeletionPolicy), deleting..."
    aws s3api delete-bucket --bucket "$LOG_BUCKET" 2>/dev/null && {
      echo "  ✓ Log bucket deleted"
      CLEANED_BUCKETS=true
    } || echo "  ⚠ Failed to delete log bucket (may already be deleted)"
  fi

  if [ "$CLEANED_BUCKETS" = false ]; then
    echo "  All buckets already cleaned up"
  fi

  echo ""
fi

echo "=========================================="
echo "✓ DESTRUCTION COMPLETE"
echo "=========================================="
echo ""
if [ "$DESTROY_BUCKETS" = true ]; then
  echo "All foundation resources have been destroyed."
else
  echo "Foundation stack destroyed. S3 buckets retained."
  echo ""
  echo "Retained buckets:"
  [ -n "$STATE_BUCKET" ] && echo "  - $STATE_BUCKET"
  [ -n "$LOG_BUCKET" ] && echo "  - $LOG_BUCKET"
  echo ""
  echo "To redeploy, run: ./scripts/deploy.sh"
  echo "(Orphaned buckets will be automatically imported)"
fi
