#!/bin/bash
# scripts/list-deployed-resources.sh - List all deployed foundation resources

set -euo pipefail

# Disable AWS CLI pager
export AWS_PAGER=""

STACK_NAME="terraform-shared-infrastructure"

echo "Listing deployed foundation resources..."
echo ""

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
  echo "✗ CloudFormation stack '$STACK_NAME' not found"
  echo "  Foundation has not been deployed yet"
  exit 1
fi

# Get stack information
echo "=== CloudFormation Stack Information ==="
STACK_STATUS=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].StackStatus' \
  --output text)

CREATION_TIME=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].CreationTime' \
  --output text)

TERMINATION_PROTECTION=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].EnableTerminationProtection' \
  --output text)

echo "Stack Name: $STACK_NAME"
echo "Status: $STACK_STATUS"
echo "Created: $CREATION_TIME"
echo "Termination Protection: $TERMINATION_PROTECTION"
echo ""

# Get stack outputs
echo "=== Stack Outputs ==="
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' \
  --output text | while IFS=$'\t' read -r key value; do
    echo "  $key: $value"
  done

echo ""

# Get specific resource details
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`TerraformStateBucket`].OutputValue' \
  --output text 2>/dev/null || echo "unknown")

TABLE=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`TerraformLockTable`].OutputValue' \
  --output text 2>/dev/null || echo "unknown")

OIDC_ARN=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`GitHubOidcProviderArn`].OutputValue' \
  --output text 2>/dev/null || echo "unknown")

# S3 Bucket Details
if [ "$BUCKET" != "unknown" ]; then
  echo "=== S3 Bucket Details ==="
  echo "Bucket: $BUCKET"
  
  # Check if bucket exists and get details
  if aws s3api head-bucket --bucket "$BUCKET" &>/dev/null; then
    echo "Status: ✓ Exists and accessible"
    
    # Versioning status
    VERSIONING=$(aws s3api get-bucket-versioning \
      --bucket "$BUCKET" \
      --query 'Status' \
      --output text 2>/dev/null || echo "Disabled")
    echo "Versioning: $VERSIONING"
    
    # Encryption status
    ENCRYPTION=$(aws s3api get-bucket-encryption \
      --bucket "$BUCKET" \
      --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
      --output text 2>/dev/null || echo "None")
    echo "Encryption: $ENCRYPTION"
    
    # Object count and size
    OBJECT_COUNT=$(aws s3 ls "s3://$BUCKET" --recursive | wc -l)
    echo "Objects: $OBJECT_COUNT"
    
    if [ "$OBJECT_COUNT" -gt 0 ]; then
      echo ""
      echo "Recent objects:"
      aws s3 ls "s3://$BUCKET" --recursive | tail -5
    fi
  else
    echo "Status: ✗ Not accessible"
  fi
  echo ""
fi

# DynamoDB Table Details
if [ "$TABLE" != "unknown" ]; then
  echo "=== DynamoDB Table Details ==="
  echo "Table: $TABLE"
  
  if aws dynamodb describe-table --table-name "$TABLE" &>/dev/null; then
    echo "Status: ✓ Exists and accessible"
    
    # Table status
    TABLE_STATUS=$(aws dynamodb describe-table \
      --table-name "$TABLE" \
      --query 'Table.TableStatus' \
      --output text)
    echo "Table Status: $TABLE_STATUS"
    
    # Billing mode
    BILLING_MODE=$(aws dynamodb describe-table \
      --table-name "$TABLE" \
      --query 'Table.BillingModeSummary.BillingMode' \
      --output text 2>/dev/null || echo "PROVISIONED")
    echo "Billing Mode: $BILLING_MODE"
    
    # Point-in-time recovery
    PITR=$(aws dynamodb describe-continuous-backups \
      --table-name "$TABLE" \
      --query 'ContinuousBackupsDescription.PointInTimeRecoveryDescription.PointInTimeRecoveryStatus' \
      --output text 2>/dev/null || echo "DISABLED")
    echo "Point-in-time Recovery: $PITR"
    
    # Item count
    ITEM_COUNT=$(aws dynamodb scan \
      --table-name "$TABLE" \
      --select COUNT \
      --query 'Count' \
      --output text 2>/dev/null || echo "0")
    echo "Active Locks: $ITEM_COUNT"
    
    if [ "$ITEM_COUNT" -gt 0 ]; then
      echo ""
      echo "Active locks:"
      aws dynamodb scan \
        --table-name "$TABLE" \
        --query 'Items[].LockID.S' \
        --output text | tr '\t' '\n' | sed 's/^/  /'
    fi
  else
    echo "Status: ✗ Not accessible"
  fi
  echo ""
fi

# OIDC Provider Details
if [ "$OIDC_ARN" != "unknown" ]; then
  echo "=== GitHub OIDC Provider Details ==="
  echo "ARN: $OIDC_ARN"
  
  if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" &>/dev/null; then
    echo "Status: ✓ Exists and accessible"
    
    # Thumbprint
    THUMBPRINT=$(aws iam get-open-id-connect-provider \
      --open-id-connect-provider-arn "$OIDC_ARN" \
      --query 'ThumbprintList[0]' \
      --output text)
    echo "Thumbprint: $THUMBPRINT"
    
    # Client IDs (audiences)
    AUDIENCES=$(aws iam get-open-id-connect-provider \
      --open-id-connect-provider-arn "$OIDC_ARN" \
      --query 'ClientIDList[]' \
      --output text)
    echo "Audiences: $AUDIENCES"
  else
    echo "Status: ✗ Not accessible"
  fi
  echo ""
fi

# Parameter Store Entries
echo "=== Parameter Store Entries ==="
PARAMETERS=(
  "/terraform/foundation/s3-state-bucket"
  "/terraform/foundation/dynamodb-lock-table"
  "/terraform/foundation/oidc-github-provider"
  "/terraform/foundation/shared-modules-repository"
)

for param in "${PARAMETERS[@]}"; do
  if aws ssm get-parameter --name "$param" &>/dev/null; then
    VALUE=$(aws ssm get-parameter --name "$param" --query 'Parameter.Value' --output text)
    echo "✓ $param = $VALUE"
  else
    echo "✗ $param (missing)"
  fi
done

echo ""
echo "✓ Foundation resource listing complete"