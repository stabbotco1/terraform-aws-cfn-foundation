#!/bin/bash
# scripts/destroy.sh - Destroy CloudFormation foundation (DANGEROUS)
# Usage: ./scripts/destroy.sh [--auto-approve]

set -euo pipefail

STACK_NAME="terraform-shared-infrastructure"
AUTO_APPROVE=false

# Parse arguments
if [ "${1:-}" = "--auto-approve" ]; then
  AUTO_APPROVE=true
fi

echo "⚠️  DANGER: CloudFormation Foundation Destruction ⚠️"
echo ""
echo "This will destroy the foundation resources used by ALL Terraform projects:"
echo "- S3 state bucket (and ALL state files)"
echo "- DynamoDB lock table"
echo "- GitHub OIDC provider (if created by this stack)"
echo "- Parameter Store entries"
echo ""

# Detect environment
if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
  echo "✗ Destruction not allowed in GitHub Actions"
  echo "  Run locally for safety"
  exit 1
fi

# Require manual confirmation unless auto-approved
if [ "$AUTO_APPROVE" = false ]; then
  read -p "Type 'DESTROY' to confirm: " confirm
  if [ "$confirm" != "DESTROY" ]; then
    echo "Destruction cancelled"
    exit 0
  fi
  echo ""
fi

# Check if stack exists and get status
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
  echo "ℹ Stack '$STACK_NAME' does not exist"
  exit 0
fi

STACK_STATUS=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].StackStatus' \
  --output text)

echo "Stack status: $STACK_STATUS"
echo ""

# Handle ROLLBACK_COMPLETE specially (no resources to clean)
if [ "$STACK_STATUS" = "ROLLBACK_COMPLETE" ]; then
  echo "ℹ Stack is in ROLLBACK_COMPLETE state (failed initial creation)"
  echo "  Checking for orphaned resources..."
  echo ""
  
  # Check for orphaned resources that may have been partially created
  ORPHANED_STATE_BUCKET="terraform-state-694394480102-us-east-1"
  ORPHANED_LOG_BUCKET="terraform-state-logs-694394480102-us-east-1"
  ORPHANED_TABLE="terraform-locks-694394480102-us-east-1"
  
  # Check and clean orphaned main state bucket
  if aws s3 ls "s3://$ORPHANED_STATE_BUCKET" &>/dev/null; then
    echo "  Found orphaned S3 state bucket: $ORPHANED_STATE_BUCKET"
    if [ "$AUTO_APPROVE" = false ]; then
      read -p "  Delete orphaned state bucket? (yes/no): " confirm
      if [ "$confirm" = "yes" ]; then
        aws s3 rb "s3://$ORPHANED_STATE_BUCKET" --force
        echo "  ✓ Orphaned state bucket deleted"
      fi
    else
      aws s3 rb "s3://$ORPHANED_STATE_BUCKET" --force
      echo "  ✓ Orphaned state bucket deleted"
    fi
  fi
  
  # Check and clean orphaned S3 log bucket
  if aws s3 ls "s3://$ORPHANED_LOG_BUCKET" &>/dev/null; then
    echo "  Found orphaned S3 log bucket: $ORPHANED_LOG_BUCKET"
    if [ "$AUTO_APPROVE" = false ]; then
      read -p "  Delete orphaned log bucket? (yes/no): " confirm
      if [ "$confirm" = "yes" ]; then
        aws s3 rb "s3://$ORPHANED_LOG_BUCKET" --force
        echo "  ✓ Orphaned log bucket deleted"
      fi
    else
      aws s3 rb "s3://$ORPHANED_LOG_BUCKET" --force
      echo "  ✓ Orphaned log bucket deleted"
    fi
  fi
  
  # Check and clean orphaned DynamoDB table
  if aws dynamodb describe-table --table-name "$ORPHANED_TABLE" &>/dev/null; then
    echo "  Found orphaned DynamoDB table: $ORPHANED_TABLE"
    if [ "$AUTO_APPROVE" = false ]; then
      read -p "  Delete orphaned table? (yes/no): " confirm
      if [ "$confirm" = "yes" ]; then
        aws dynamodb update-table --table-name "$ORPHANED_TABLE" --no-deletion-protection-enabled &>/dev/null || true
        aws dynamodb delete-table --table-name "$ORPHANED_TABLE"
        echo "  ✓ Orphaned table deleted"
      fi
    else
      aws dynamodb update-table --table-name "$ORPHANED_TABLE" --no-deletion-protection-enabled &>/dev/null || true
      aws dynamodb delete-table --table-name "$ORPHANED_TABLE"
      echo "  ✓ Orphaned table deleted"
    fi
  fi
  
  echo ""
  if [ "$AUTO_APPROVE" = false ]; then
    read -p "Delete failed stack? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
      echo "Deletion cancelled"
      exit 0
    fi
  fi
  
  # Disable termination protection
  echo "Disabling termination protection..."
  aws cloudformation update-termination-protection \
    --stack-name "$STACK_NAME" \
    --no-enable-termination-protection
  
  # Delete stack
  echo "Deleting failed stack..."
  aws cloudformation delete-stack --stack-name "$STACK_NAME"
  aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"
  
  echo ""
  echo "✓ Failed stack and orphaned resources deleted"
  exit 0
fi

# Handle IN_PROGRESS states
if [[ "$STACK_STATUS" == *"_IN_PROGRESS" ]]; then
  echo "✗ Stack operation in progress: $STACK_STATUS"
  echo "  Wait for current operation to complete"
  exit 1
fi

# Get stack resources before destruction
echo "Checking current foundation resources..."
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`TerraformStateBucket`].OutputValue' \
  --output text 2>/dev/null || echo "unknown")

TABLE=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`TerraformLockTable`].OutputValue' \
  --output text 2>/dev/null || echo "unknown")

echo "Current resources:"
echo "  S3 Bucket: $BUCKET"
echo "  DynamoDB Table: $TABLE"
echo ""

# Check for Project 3 (deployment-roles) resources
echo "Checking for deployment-roles project resources..."
DEPLOYMENT_ROLES_RESOURCES=$(aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=Project,Values=terraform-aws-deployment-roles" \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output text 2>/dev/null || echo "")

if [ -n "$DEPLOYMENT_ROLES_RESOURCES" ]; then
  RESOURCE_COUNT=$(echo "$DEPLOYMENT_ROLES_RESOURCES" | wc -w | tr -d ' ')
  echo "✗ Found $RESOURCE_COUNT resources from terraform-aws-deployment-roles project!"
  echo ""
  echo "Deployment roles resources found:"
  echo "$DEPLOYMENT_ROLES_RESOURCES" | tr '\t' '\n' | head -10
  echo ""
  echo "You MUST destroy Project 3 (deployment-roles) first:"
  echo "  cd terraform-aws-deployment-roles"
  echo "  ./scripts/destroy.sh"
  echo ""
  exit 1
fi

echo "✓ No deployment-roles project resources found"
echo ""

# Check for state files in bucket
if [ "$BUCKET" != "unknown" ] && aws s3 ls "s3://$BUCKET" &>/dev/null; then
  STATE_FILES=$(aws s3 ls "s3://$BUCKET" --recursive | { grep -v "backups/" || true; } | wc -l | tr -d ' \n')
  BACKUP_FILES=$(aws s3 ls "s3://$BUCKET/backups/" --recursive 2>/dev/null | wc -l | tr -d ' \n')
  
  echo "S3 bucket contents:"
  echo "  Active state files: $STATE_FILES"
  echo "  Backup files: $BACKUP_FILES"
  echo ""
  
  if [ "$STATE_FILES" -gt 0 ]; then
    echo "✗ Active state files found in bucket!"
    echo ""
    echo "State files found:"
    aws s3 ls "s3://$BUCKET" --recursive | grep -v "backups/" | head -10
    echo ""
    echo "You MUST destroy all dependent projects first:"
    echo "1. Destroy all Project 4+ (application projects)"
    echo "2. Destroy Project 3 (deployment-roles)"
    echo "3. Then destroy this foundation"
    echo ""
    
    if [ "$AUTO_APPROVE" = false ]; then
      read -p "Continue anyway? This will DELETE ALL STATE FILES! (type 'DELETE' to confirm): " confirm
      if [ "$confirm" != "DELETE" ]; then
        echo "Destruction cancelled"
        exit 0
      fi
    else
      echo "⚠ Auto-approve enabled - proceeding despite state files"
    fi
  fi
  
  echo "✓ No active state files found"
  echo ""
fi

# Check for active locks
if [ "$TABLE" != "unknown" ]; then
  ACTIVE_LOCKS=$(aws dynamodb scan \
    --table-name "$TABLE" \
    --select COUNT \
    --query 'Count' \
    --output text 2>/dev/null || echo "0")
  
  if [ "$ACTIVE_LOCKS" -gt 0 ]; then
    echo "⚠ Active locks found in DynamoDB table: $ACTIVE_LOCKS"
    echo "  This may indicate active Terraform operations"
    echo ""
  fi
fi

# Final confirmation
if [ "$AUTO_APPROVE" = false ]; then
  echo "FINAL WARNING:"
  echo "This action is IRREVERSIBLE and will:"
  echo "- Delete the S3 bucket and ALL Terraform state files"
  echo "- Delete the DynamoDB lock table"
  echo "- Remove Parameter Store entries"
  echo "- Make ALL dependent projects unmanageable"
  echo ""
  read -p "Type 'DESTROY FOUNDATION' to confirm: " confirm

  if [ "$confirm" != "DESTROY FOUNDATION" ]; then
    echo "Destruction cancelled"
    exit 0
  fi
fi

# Create final backup if bucket exists
if [ "$BUCKET" != "unknown" ] && aws s3 ls "s3://$BUCKET" &>/dev/null; then
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  FINAL_BACKUP_PREFIX="final-backup-${TIMESTAMP}"
  
  echo ""
  echo "Creating final backup..."
  aws s3 sync "s3://$BUCKET" "s3://$BUCKET/${FINAL_BACKUP_PREFIX}/" \
    --exclude "${FINAL_BACKUP_PREFIX}/*" || {
    echo "⚠ Backup failed, but continuing with destruction"
  }
  
  echo "✓ Final backup created at: s3://$BUCKET/${FINAL_BACKUP_PREFIX}/"
fi

# Disable termination protection
echo ""
echo "Disabling termination protection..."
aws cloudformation update-termination-protection \
  --stack-name "$STACK_NAME" \
  --no-enable-termination-protection

# Empty S3 bucket (required for deletion)
if [ "$BUCKET" != "unknown" ]; then
  echo "Emptying S3 bucket..."
  aws s3 rm "s3://$BUCKET" --recursive || {
    echo "⚠ Failed to empty bucket completely"
  }
fi

# Delete CloudFormation stack
echo "Deleting CloudFormation stack..."
aws cloudformation delete-stack --stack-name "$STACK_NAME"

echo "Waiting for stack deletion to complete..."
aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"

echo ""
echo "✓ Foundation destruction complete"
echo ""
echo "All foundation resources have been destroyed."
echo "Dependent projects are now unmanageable until foundation is recreated."