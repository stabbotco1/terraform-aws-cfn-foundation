#!/bin/bash
# scripts/deploy.sh - Deploy CloudFormation foundation

set -euo pipefail

echo "Deploying CloudFormation foundation..."

# Detect environment
if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
    echo "Running in GitHub Actions"
    INTERACTIVE=false
else
    echo "Running locally"
    INTERACTIVE=true
fi

# Verify prerequisites
echo ""
echo "Step 1: Verifying prerequisites..."
./scripts/verify-prerequisites.sh || exit 1

# Check for existing OIDC provider
echo ""
echo "Step 2: Checking for existing OIDC provider..."
EXISTING_OIDC=$(aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn" \
  --output text 2>/dev/null || echo "")

if [ -n "$EXISTING_OIDC" ]; then
  echo "ℹ Existing OIDC provider found: $EXISTING_OIDC"
  echo "  Will reuse existing provider"
  OIDC_ACTION="reuse"
  
  # Validate existing provider
  echo "  Validating existing provider..."
  THUMBPRINT=$(aws iam get-open-id-connect-provider \
    --open-id-connect-provider-arn "$EXISTING_OIDC" \
    --query 'ThumbprintList[0]' \
    --output text 2>/dev/null || echo "")
  
  EXPECTED_THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"
  
  if [ "$THUMBPRINT" = "$EXPECTED_THUMBPRINT" ]; then
    echo "  ✓ Thumbprint is valid"
  else
    echo "  ⚠ Thumbprint mismatch - may need update"
    echo "    Expected: $EXPECTED_THUMBPRINT"
    echo "    Found: $THUMBPRINT"
  fi
  
  # Validate audience
  AUDIENCES=$(aws iam get-open-id-connect-provider \
    --open-id-connect-provider-arn "$EXISTING_OIDC" \
    --query 'ClientIDList' \
    --output json 2>/dev/null || echo "[]")
  
  if echo "$AUDIENCES" | grep -q "sts.amazonaws.com"; then
    echo "  ✓ Audience includes sts.amazonaws.com"
  else
    echo "  ⚠ Missing required audience: sts.amazonaws.com"
  fi
else
  echo "ℹ No existing OIDC provider - will create new one"
  OIDC_ACTION="create"
fi

# Check for existing stack
STACK_NAME="terraform-shared-infrastructure"
echo ""
echo "Step 3: Checking for existing CloudFormation stack..."

if aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
  STACK_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].StackStatus' \
    --output text)
  
  echo "ℹ Stack '$STACK_NAME' exists with status: $STACK_STATUS"
  
  case "$STACK_STATUS" in
    ROLLBACK_COMPLETE)
      echo "⚠ Stack is in ROLLBACK_COMPLETE state (failed initial creation)"
      echo "  Must delete and recreate"
      
      # Disable termination protection if enabled
      aws cloudformation update-termination-protection \
        --stack-name "$STACK_NAME" \
        --no-enable-termination-protection &>/dev/null || true
      
      echo "  Deleting failed stack..."
      aws cloudformation delete-stack --stack-name "$STACK_NAME"
      aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"
      echo "✓ Failed stack deleted - will create new stack"
      ACTION="create"
      ;;
    UPDATE_ROLLBACK_COMPLETE)
      echo "ℹ Stack is in UPDATE_ROLLBACK_COMPLETE state (failed update)"
      echo "  Stack will be updated"
      
      if [ "$INTERACTIVE" = "true" ]; then
        read -p "Update existing stack? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
          echo "Deployment cancelled"
          exit 0
        fi
      fi
      ACTION="update"
      ;;
    CREATE_COMPLETE|UPDATE_COMPLETE)
      echo "ℹ Stack is healthy"
      
      if [ "$INTERACTIVE" = "true" ]; then
        read -p "Update existing stack? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
          echo "Deployment cancelled"
          exit 0
        fi
      else
        echo "  Updating existing stack..."
      fi
      ACTION="update"
      ;;
    *_IN_PROGRESS)
      echo "✗ Stack operation in progress: $STACK_STATUS"
      echo "  Wait for current operation to complete"
      exit 1
      ;;
    *)
      echo "⚠ Unexpected stack status: $STACK_STATUS"
      echo "  Attempting to proceed with update"
      ACTION="update"
      ;;
  esac
else
  echo "ℹ Stack '$STACK_NAME' does not exist - will create"
  ACTION="create"
fi

# Deploy CloudFormation stack
echo ""
echo "Step 4: Deploying CloudFormation stack..."

if [ "$ACTION" = "create" ]; then
  aws cloudformation create-stack \
    --stack-name "$STACK_NAME" \
    --template-body file://bootstrap.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=OidcAction,ParameterValue="$OIDC_ACTION" \
    --enable-termination-protection \
    --tags Key=Purpose,Value=TerraformFoundation Key=ManagedBy,Value=CloudFormation

  echo "✓ CloudFormation stack creation initiated"
  echo "  Waiting for stack creation to complete..."

  aws cloudformation wait stack-create-complete \
    --stack-name "$STACK_NAME"
else
  aws cloudformation update-stack \
    --stack-name "$STACK_NAME" \
    --template-body file://bootstrap.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=OidcAction,ParameterValue="$OIDC_ACTION"

  echo "✓ CloudFormation stack update initiated"
  echo "  Waiting for stack update to complete..."

  aws cloudformation wait stack-update-complete \
    --stack-name "$STACK_NAME"
fi

echo ""
echo "Step 5: Verifying deployment..."

# Get stack outputs
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`TerraformStateBucket`].OutputValue' \
  --output text)

TABLE=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`TerraformLockTable`].OutputValue' \
  --output text)

OIDC_ARN=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`GitHubOidcProviderArn`].OutputValue' \
  --output text)

echo "✓ Foundation deployment complete"
echo ""
echo "Resources created:"
echo "  S3 State Bucket: $BUCKET"
echo "  DynamoDB Lock Table: $TABLE"
echo "  GitHub OIDC Provider: $OIDC_ARN"
echo ""
echo "Parameter Store entries created:"
echo "  /terraform/foundation/s3-state-bucket"
echo "  /terraform/foundation/dynamodb-lock-table"
echo "  /terraform/foundation/oidc-github-provider"
echo "  /terraform/foundation/shared-modules-repository"
echo ""
echo "Next steps:"
echo "1. Deploy Project 2: terraform-aws-shared-modules"
echo "2. Deploy Project 3: terraform-aws-deployment-roles"
echo "3. Deploy Project 4+: Application projects"