#!/bin/bash
# scripts/destroy.sh - Destroy CloudFormation foundation and all resources

set -euo pipefail

# Disable AWS CLI pager
export AWS_PAGER=""

STACK_NAME="terraform-shared-infrastructure"

# Verify prerequisites (includes git state checks)
echo "Verifying prerequisites..."
./scripts/verify-prerequisites.sh || exit 1

echo ""
echo "=========================================="
echo "TERRAFORM FOUNDATION DESTRUCTION"
echo "=========================================="
echo ""
echo "⚠️  WARNING: This will permanently delete:"
echo "  - CloudFormation stack: $STACK_NAME"
echo "  - DynamoDB lock table (always deleted)"
echo "  - All SSM parameters"
echo "  - S3 buckets (optional - see next prompt)"
echo ""
echo "This action is IRREVERSIBLE."
echo ""

# Require DESTROY confirmation
read -p "Type 'DESTROY' to confirm: " confirmation

if [ "$confirmation" != "DESTROY" ]; then
  echo "Destruction cancelled"
  exit 0
fi

# Ask about S3 buckets
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

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
  echo "✗ Stack '$STACK_NAME' not found"
  
  if [ "$DESTROY_BUCKETS" = true ]; then
    echo "Checking for orphaned buckets..."
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region || echo "us-east-1")
    STATE_BUCKET="terraform-state-${ACCOUNT_ID}-${REGION}"
    LOG_BUCKET="terraform-state-logs-${ACCOUNT_ID}-${REGION}"
    
    if aws s3 ls "s3://$STATE_BUCKET" &>/dev/null; then
      echo "Found orphaned state bucket: $STATE_BUCKET"
      echo "Emptying and deleting..."
      
      # Delete all versions
      aws s3api list-object-versions \
        --bucket "$STATE_BUCKET" \
        --output json \
        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' 2>/dev/null | \
      jq -r '.Objects[]? | "--key \(.Key) --version-id \(.VersionId)"' | \
      xargs -I {} -P 10 aws s3api delete-object --bucket "$STATE_BUCKET" {} &>/dev/null || true
      
      # Delete all delete markers
      aws s3api list-object-versions \
        --bucket "$STATE_BUCKET" \
        --output json \
        --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' 2>/dev/null | \
      jq -r '.Objects[]? | "--key \(.Key) --version-id \(.VersionId)"' | \
      xargs -I {} -P 10 aws s3api delete-object --bucket "$STATE_BUCKET" {} &>/dev/null || true
      
      aws s3 rm "s3://$STATE_BUCKET" --recursive &>/dev/null || true
      aws s3api delete-bucket --bucket "$STATE_BUCKET"
      echo "✓ Deleted $STATE_BUCKET"
    fi
    
    if aws s3 ls "s3://$LOG_BUCKET" &>/dev/null; then
      echo "Found orphaned log bucket: $LOG_BUCKET"
      echo "Emptying and deleting..."
      
      aws s3api list-object-versions \
        --bucket "$LOG_BUCKET" \
        --output json \
        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' 2>/dev/null | \
      jq -r '.Objects[]? | "--key \(.Key) --version-id \(.VersionId)"' | \
      xargs -I {} -P 10 aws s3api delete-object --bucket "$LOG_BUCKET" {} &>/dev/null || true
      
      aws s3api list-object-versions \
        --bucket "$LOG_BUCKET" \
        --output json \
        --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' 2>/dev/null | \
      jq -r '.Objects[]? | "--key \(.Key) --version-id \(.VersionId)"' | \
      xargs -I {} -P 10 aws s3api delete-object --bucket "$LOG_BUCKET" {} &>/dev/null || true
      
      aws s3 rm "s3://$LOG_BUCKET" --recursive &>/dev/null || true
      aws s3api delete-bucket --bucket "$LOG_BUCKET"
      echo "✓ Deleted $LOG_BUCKET"
    fi
  fi
  
  exit 0
fi

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
  if [ -n "$STATE_BUCKET" ]; then
    echo "Step 4: Emptying S3 state bucket..."
    
    # Delete all object versions
    echo "  Deleting all object versions..."
    aws s3api list-object-versions \
      --bucket "$STATE_BUCKET" \
      --output json \
      --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' 2>/dev/null | \
    jq -r '.Objects[]? | "--key \(.Key) --version-id \(.VersionId)"' | \
    xargs -I {} -P 10 aws s3api delete-object --bucket "$STATE_BUCKET" {} &>/dev/null || true
    
    # Delete all delete markers
    echo "  Deleting all delete markers..."
    aws s3api list-object-versions \
      --bucket "$STATE_BUCKET" \
      --output json \
      --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' 2>/dev/null | \
    jq -r '.Objects[]? | "--key \(.Key) --version-id \(.VersionId)"' | \
    xargs -I {} -P 10 aws s3api delete-object --bucket "$STATE_BUCKET" {} &>/dev/null || true
    
    # Final cleanup
    aws s3 rm "s3://$STATE_BUCKET" --recursive &>/dev/null || true
    
    echo "✓ State bucket emptied"
    echo ""
  fi
  
  if [ -n "$LOG_BUCKET" ]; then
    echo "Step 5: Emptying S3 log bucket..."
    
    # Delete all object versions
    aws s3api list-object-versions \
      --bucket "$LOG_BUCKET" \
      --output json \
      --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' 2>/dev/null | \
    jq -r '.Objects[]? | "--key \(.Key) --version-id \(.VersionId)"' | \
    xargs -I {} -P 10 aws s3api delete-object --bucket "$LOG_BUCKET" {} &>/dev/null || true
    
    # Delete all delete markers
    aws s3api list-object-versions \
      --bucket "$LOG_BUCKET" \
      --output json \
      --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' 2>/dev/null | \
    jq -r '.Objects[]? | "--key \(.Key) --version-id \(.VersionId)"' | \
    xargs -I {} -P 10 aws s3api delete-object --bucket "$LOG_BUCKET" {} &>/dev/null || true
    
    # Final cleanup
    aws s3 rm "s3://$LOG_BUCKET" --recursive &>/dev/null || true
    
    echo "✓ Log bucket emptied"
    echo ""
  fi
fi

# Step 6: Delete CloudFormation stack
echo "Step 6: Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name "$STACK_NAME"
echo "  Waiting for stack deletion to complete..."
aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" 2>/dev/null || {
  echo "  Stack deletion encountered an issue, checking status..."
  STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DELETED")
  
  if [ "$STACK_STATUS" = "DELETE_FAILED" ]; then
    echo "⚠ Stack deletion failed, checking for remaining resources..."
  else
    echo "✓ Stack deleted"
  fi
}
echo ""

# Step 7: Clean up remaining S3 buckets if requested
if [ "$DESTROY_BUCKETS" = true ]; then
  echo "Step 7: Cleaning up remaining S3 buckets..."
  
  if [ -n "$STATE_BUCKET" ] && aws s3 ls "s3://$STATE_BUCKET" &>/dev/null; then
    echo "  Deleting state bucket..."
    aws s3api delete-bucket --bucket "$STATE_BUCKET" 2>/dev/null || true
    echo "  ✓ State bucket deleted"
  fi
  
  if [ -n "$LOG_BUCKET" ] && aws s3 ls "s3://$LOG_BUCKET" &>/dev/null; then
    echo "  Deleting log bucket..."
    aws s3api delete-bucket --bucket "$LOG_BUCKET" 2>/dev/null || true
    echo "  ✓ Log bucket deleted"
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
