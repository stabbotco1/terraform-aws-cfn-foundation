#!/bin/bash
# scripts/deploy.sh - Deploy CloudFormation foundation

set -euo pipefail

# Disable AWS CLI pager
export AWS_PAGER=""

echo "Deploying CloudFormation foundation..."

# Verify prerequisites (includes git state checks)
echo ""
echo "Step 1: Verifying prerequisites..."
./scripts/verify-prerequisites.sh || exit 1

# Load environment variables from .env file
if [ -f ".env" ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Collect deployment metadata
echo ""
echo "Step 2: Collecting deployment metadata..."

# Get repository URL (normalize to HTTPS, keep .git)
REPOSITORY=$(git remote get-url origin | sed 's|git@github.com:|https://github.com/|')
echo "  Repository: $REPOSITORY"

# Extract project name (remove .git)
PROJECT=$(echo "$REPOSITORY" | sed -E 's|.*/([^/]+)\.git$|\1|')
echo "  Project: $PROJECT"

# Get environment from .env or default
ENVIRONMENT=${TAG_ENVIRONMENT:-"Development"}
echo "  Environment: $ENVIRONMENT"

# Get owner from .env or default
OWNER=${TAG_OWNER:-"Unknown"}
echo "  Owner: $OWNER"

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "  Account ID: $ACCOUNT_ID"

# Get AWS Region from .env or AWS CLI config
REGION=${AWS_REGION:-$(aws configure get region || echo "us-east-1")}
echo "  Region: $REGION"

# Get deployer ARN
DEPLOYED_BY=$(aws sts get-caller-identity --query Arn --output text)
echo "  Deployed By: $DEPLOYED_BY"

# Managed by
MANAGED_BY=${TAG_MANAGED_BY:-"CloudFormation"}
echo "  Managed By: $MANAGED_BY"

# Deployment ID
DEPLOYMENT_ID=${TAG_DEPLOYMENT_ID:-"Default"}
echo "  Deployment ID: $DEPLOYMENT_ID"

# Testing mode - force stack update
FORCE_UPDATE=${TESTING_FORCE_STACK_UPDATE:-"false"}
if [ "$FORCE_UPDATE" = "true" ]; then
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "  ⚠️  Testing Mode: Forcing stack update with timestamp: $TIMESTAMP"
else
  TIMESTAMP="not-set"
fi

# Detect OIDC provider from git remote
echo ""
echo "Step 3: Detecting OIDC provider from repository..."

detect_oidc_provider() {
  local repo_url="$1"
  
  if [[ "$repo_url" =~ github\.com ]]; then
    echo "github"
  elif [[ "$repo_url" =~ gitlab\.com ]]; then
    echo "gitlab"
  elif [[ "$repo_url" =~ bitbucket\.org ]]; then
    echo "bitbucket"
  else
    echo "unsupported"
  fi
}

calculate_thumbprint() {
  local url="$1"
  
  # Extract host from URL
  local host=$(echo "$url" | sed -E 's|https?://([^/]+).*|\1|')
  
  # Get certificate and calculate thumbprint
  local thumbprint=$(echo | openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null | \
    openssl x509 -fingerprint -sha1 -noout 2>/dev/null | \
    cut -d'=' -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')
  
  if [ -z "$thumbprint" ]; then
    echo "ERROR: Failed to calculate thumbprint for $url" >&2
    return 1
  fi
  
  echo "$thumbprint"
}

OIDC_PROVIDER=$(detect_oidc_provider "$REPOSITORY")

case "$OIDC_PROVIDER" in
  github)
    echo "  Provider: GitHub"
    OIDC_URL="https://token.actions.githubusercontent.com"
    OIDC_AUDIENCE="sts.amazonaws.com"
    # GitHub requires both thumbprints for reliability
    OIDC_THUMBPRINTS="6938fd4d98bab03faadb97b34396831e3780aea1,1c58a3a8518e8759bf075b76b750d4f2df264fcd"
    echo "  URL: $OIDC_URL"
    echo "  Audience: $OIDC_AUDIENCE"
    echo "  Thumbprints: Using GitHub's known thumbprints"
    ;;
  
  gitlab)
    echo "  Provider: GitLab"
    OIDC_URL="https://gitlab.com"
    OIDC_AUDIENCE="sts.amazonaws.com"
    echo "  URL: $OIDC_URL"
    echo "  Calculating thumbprint..."
    OIDC_THUMBPRINTS=$(calculate_thumbprint "$OIDC_URL")
    if [ $? -ne 0 ]; then
      echo "✗ Failed to calculate GitLab thumbprint"
      echo "  Please ensure openssl is installed and gitlab.com is accessible"
      exit 1
    fi
    echo "  Thumbprint: $OIDC_THUMBPRINTS"
    echo "  Audience: $OIDC_AUDIENCE"
    ;;
  
  bitbucket)
    echo "  Provider: Bitbucket"
    # Extract workspace from Bitbucket URL
    # Format: https://bitbucket.org/workspace/repo or git@bitbucket.org:workspace/repo
    WORKSPACE=$(echo "$REPOSITORY" | sed -E 's|.*bitbucket\.org[:/]([^/]+)/.*|\1|')
    
    if [ -z "$WORKSPACE" ]; then
      echo "✗ Failed to extract Bitbucket workspace from repository URL"
      exit 1
    fi
    
    OIDC_URL="https://api.bitbucket.org/2.0/workspaces/$WORKSPACE/pipelines-config/identity/oidc"
    OIDC_AUDIENCE="ari:cloud:bitbucket::workspace/$WORKSPACE"
    OIDC_THUMBPRINTS="a031c46782e6e6c662c2c87c76da9aa62ccabd8e"
    echo "  Workspace: $WORKSPACE"
    echo "  URL: $OIDC_URL"
    echo "  Audience: $OIDC_AUDIENCE"
    echo "  Thumbprint: Using Bitbucket's known thumbprint"
    ;;
  
  unsupported)
    echo "✗ Unsupported git provider"
    echo "  Repository: $REPOSITORY"
    echo ""
    echo "Supported providers:"
    echo "  - GitHub (github.com)"
    echo "  - GitLab (gitlab.com)"
    echo "  - Bitbucket (bitbucket.org)"
    echo ""
    echo "For self-hosted or other providers, please configure OIDC manually."
    exit 1
    ;;
esac

# Define resource names
STATE_BUCKET="terraform-state-${ACCOUNT_ID}-${REGION}"
LOG_BUCKET="terraform-state-logs-${ACCOUNT_ID}-${REGION}"
STACK_NAME="terraform-shared-infrastructure"

# Check for existing stack first
echo ""
echo "Step 4: Checking for existing CloudFormation stack..."

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

      # Function to safely delete a versioned S3 bucket
      delete_versioned_bucket() {
        local bucket=$1

        if ! aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
          return 0  # Bucket doesn't exist, nothing to do
        fi

        echo "  Cleaning up bucket: $bucket"

        # Delete all object versions
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
        aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true
      }

      # Clean up orphaned buckets from failed creation
      delete_versioned_bucket "$STATE_BUCKET"
      delete_versioned_bucket "$LOG_BUCKET"

      # Check and clean up OIDC provider if it exists
      OIDC_PROVIDER_ARN=$(aws iam list-open-id-connect-providers \
        --query "OpenIDConnectProviderList[?contains(Arn, '${OIDC_URL#https://}')].Arn" \
        --output text 2>/dev/null || echo "")

      if [ -n "$OIDC_PROVIDER_ARN" ]; then
        echo "  Cleaning up orphaned OIDC provider: $OIDC_PROVIDER_ARN"
        aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" 2>/dev/null || true
      fi

      # Disable termination protection if enabled
      aws cloudformation update-termination-protection \
        --stack-name "$STACK_NAME" \
        --no-enable-termination-protection &>/dev/null || true

      echo "  Deleting failed stack..."
      aws cloudformation delete-stack --stack-name "$STACK_NAME"
      echo "  Waiting for stack deletion..."
      aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"
      echo "✓ Failed stack and orphaned resources cleaned up - will create new stack"
      ACTION="create"
      ;;
    UPDATE_ROLLBACK_COMPLETE)
      echo "ℹ Stack is in UPDATE_ROLLBACK_COMPLETE state (failed update)"
      echo "  Stack will be updated"
      ACTION="update"
      ;;
    CREATE_COMPLETE|UPDATE_COMPLETE|IMPORT_COMPLETE)
      echo "ℹ Stack is healthy - updating existing stack"
      ACTION="update"
      ;;
    CREATE_IN_PROGRESS|UPDATE_IN_PROGRESS|DELETE_IN_PROGRESS|IMPORT_IN_PROGRESS)
      echo "✗ Stack operation in progress: $STACK_STATUS"
      echo "  Please wait for the current operation to complete and try again"
      exit 1
      ;;
    DELETE_FAILED)
      echo "⚠ Stack is in DELETE_FAILED state"
      echo "  Manual intervention may be required"
      echo "  Check the CloudFormation console for details on resources that failed to delete"
      exit 1
      ;;
    *)
      echo "⚠ Unexpected stack status: $STACK_STATUS"
      echo "  Attempting to proceed with update"
      ACTION="update"
      ;;
  esac
else
  echo "ℹ Stack '$STACK_NAME' does not exist"

  # Check for orphaned buckets (stack doesn't exist but buckets might)
  detect_bucket_state() {
    local bucket=$1
    if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
      echo "orphaned"
    else
      echo "none"
    fi
  }

  STATE_BUCKET_STATE=$(detect_bucket_state "$STATE_BUCKET")
  LOG_BUCKET_STATE=$(detect_bucket_state "$LOG_BUCKET")

  if [ "$STATE_BUCKET_STATE" = "orphaned" ] || [ "$LOG_BUCKET_STATE" = "orphaned" ]; then
    echo "ℹ Orphaned S3 buckets detected from previous deployment"
    echo "  State bucket: $STATE_BUCKET_STATE"
    echo "  Log bucket: $LOG_BUCKET_STATE"
    echo ""
    echo "  Options:"
    echo "    1. Import buckets into new stack (preserves existing state/logs)"
    echo "    2. Delete buckets and create fresh (destroys all state/logs)"
    echo ""
    read -p "Import buckets? (y/N): " IMPORT_CHOICE

    if [[ "$IMPORT_CHOICE" =~ ^[Yy]$ ]]; then
      echo "  Will import orphaned buckets into stack"
      ACTION="import"
    else
      echo "  Will delete orphaned buckets and create fresh"

      # Function to safely delete a versioned S3 bucket
      delete_versioned_bucket() {
        local bucket=$1

        if ! aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
          return 0  # Bucket doesn't exist, nothing to do
        fi

        echo "  Deleting bucket: $bucket"

        # Delete all object versions
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
        aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true
      }

      delete_versioned_bucket "$STATE_BUCKET"
      delete_versioned_bucket "$LOG_BUCKET"
      echo "✓ Orphaned buckets cleaned up"
      ACTION="create"
    fi
  else
    ACTION="create"
  fi
fi

# Deploy CloudFormation stack
echo ""
echo "Step 5: Deploying CloudFormation stack..."

if [ "$ACTION" = "import" ]; then
  # Import orphaned buckets into a new stack
  echo "Creating stack with bucket import..."

  # Build import resources JSON
  cat > /tmp/resources-to-import.json <<EOF
[
EOF

  FIRST=true
  if [ "$STATE_BUCKET_STATE" = "orphaned" ]; then
    cat >> /tmp/resources-to-import.json <<EOF
  {
    "ResourceType": "AWS::S3::Bucket",
    "LogicalResourceId": "TerraformStateBucket",
    "ResourceIdentifier": {
      "BucketName": "$STATE_BUCKET"
    }
  }
EOF
    FIRST=false
  fi

  if [ "$LOG_BUCKET_STATE" = "orphaned" ]; then
    [ "$FIRST" = false ] && echo "," >> /tmp/resources-to-import.json
    cat >> /tmp/resources-to-import.json <<EOF
  {
    "ResourceType": "AWS::S3::Bucket",
    "LogicalResourceId": "TerraformStateLogBucket",
    "ResourceIdentifier": {
      "BucketName": "$LOG_BUCKET"
    }
  }
EOF
    FIRST=false
  fi

  cat >> /tmp/resources-to-import.json <<EOF

]
EOF

  # Create import changeset
  echo "  Creating import changeset..."
  CHANGESET_NAME="import-buckets-$(date +%s)"

  aws cloudformation create-change-set \
    --stack-name "$STACK_NAME" \
    --change-set-name "$CHANGESET_NAME" \
    --change-set-type IMPORT \
    --resources-to-import file:///tmp/resources-to-import.json \
    --template-body file://bootstrap.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters \
      ParameterKey=LastDeploymentTimestamp,ParameterValue="$TIMESTAMP" \
      ParameterKey=Project,ParameterValue="$PROJECT" \
      ParameterKey=Repository,ParameterValue="$REPOSITORY" \
      ParameterKey=Environment,ParameterValue="$ENVIRONMENT" \
      ParameterKey=Owner,ParameterValue="$OWNER" \
      ParameterKey=DeployedBy,ParameterValue="$DEPLOYED_BY" \
      ParameterKey=ManagedBy,ParameterValue="$MANAGED_BY" \
      ParameterKey=DeploymentID,ParameterValue="$DEPLOYMENT_ID" \
      ParameterKey=OidcProvider,ParameterValue="$OIDC_PROVIDER" \
      ParameterKey=OidcUrl,ParameterValue="$OIDC_URL" \
      ParameterKey=OidcThumbprints,ParameterValue=\"$OIDC_THUMBPRINTS\" \
      ParameterKey=OidcAudience,ParameterValue="$OIDC_AUDIENCE" \
    --tags \
      Key=Project,Value="$PROJECT" \
      Key=Repository,Value="$REPOSITORY" \
      Key=Environment,Value="$ENVIRONMENT" \
      Key=Owner,Value="$OWNER" \
      Key=AccountId,Value="$ACCOUNT_ID" \
      Key=Region,Value="$REGION" \
      Key=DeployedBy,Value="$DEPLOYED_BY" \
      Key=ManagedBy,Value="$MANAGED_BY" \
      Key=DeploymentID,Value="$DEPLOYMENT_ID" 2>&1 || {
    echo "✗ Failed to create import changeset"
    echo "  This can happen if bucket configurations don't match the template"
    rm -f /tmp/resources-to-import.json
    exit 1
  }

  # Wait for changeset to be created
  echo "  Waiting for changeset creation..."
  sleep 5

  # Execute the changeset
  echo "  Executing changeset..."
  aws cloudformation execute-change-set \
    --stack-name "$STACK_NAME" \
    --change-set-name "$CHANGESET_NAME"

  echo "  Waiting for import to complete..."
  aws cloudformation wait stack-import-complete --stack-name "$STACK_NAME" 2>&1 || {
    echo "✗ Import failed"
    rm -f /tmp/resources-to-import.json
    exit 1
  }

  # Enable termination protection
  aws cloudformation update-termination-protection \
    --stack-name "$STACK_NAME" \
    --enable-termination-protection &>/dev/null || true

  rm -f /tmp/resources-to-import.json
  echo "✓ Stack created with imported buckets"

elif [ "$ACTION" = "create" ]; then
  aws cloudformation create-stack \
    --stack-name "$STACK_NAME" \
    --template-body file://bootstrap.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters \
      ParameterKey=LastDeploymentTimestamp,ParameterValue="$TIMESTAMP" \
      ParameterKey=Project,ParameterValue="$PROJECT" \
      ParameterKey=Repository,ParameterValue="$REPOSITORY" \
      ParameterKey=Environment,ParameterValue="$ENVIRONMENT" \
      ParameterKey=Owner,ParameterValue="$OWNER" \
      ParameterKey=DeployedBy,ParameterValue="$DEPLOYED_BY" \
      ParameterKey=ManagedBy,ParameterValue="$MANAGED_BY" \
      ParameterKey=DeploymentID,ParameterValue="$DEPLOYMENT_ID" \
      ParameterKey=OidcProvider,ParameterValue="$OIDC_PROVIDER" \
      ParameterKey=OidcUrl,ParameterValue="$OIDC_URL" \
      ParameterKey=OidcThumbprints,ParameterValue=\"$OIDC_THUMBPRINTS\" \
      ParameterKey=OidcAudience,ParameterValue="$OIDC_AUDIENCE" \
    --enable-termination-protection \
    --tags \
      Key=Project,Value="$PROJECT" \
      Key=Repository,Value="$REPOSITORY" \
      Key=Environment,Value="$ENVIRONMENT" \
      Key=Owner,Value="$OWNER" \
      Key=AccountId,Value="$ACCOUNT_ID" \
      Key=Region,Value="$REGION" \
      Key=DeployedBy,Value="$DEPLOYED_BY" \
      Key=ManagedBy,Value="$MANAGED_BY" \
      Key=DeploymentID,Value="$DEPLOYMENT_ID"

  echo "✓ CloudFormation stack creation initiated"
  echo "  Waiting for stack creation to complete..."

  aws cloudformation wait stack-create-complete \
    --stack-name "$STACK_NAME"
else
  # Capture output to handle "No updates" error
  UPDATE_OUTPUT=$(aws cloudformation update-stack \
    --stack-name "$STACK_NAME" \
    --template-body file://bootstrap.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters \
      ParameterKey=LastDeploymentTimestamp,ParameterValue="$TIMESTAMP" \
      ParameterKey=Project,ParameterValue="$PROJECT" \
      ParameterKey=Repository,ParameterValue="$REPOSITORY" \
      ParameterKey=Environment,ParameterValue="$ENVIRONMENT" \
      ParameterKey=Owner,ParameterValue="$OWNER" \
      ParameterKey=DeployedBy,ParameterValue="$DEPLOYED_BY" \
      ParameterKey=ManagedBy,ParameterValue="$MANAGED_BY" \
      ParameterKey=DeploymentID,ParameterValue="$DEPLOYMENT_ID" \
      ParameterKey=OidcProvider,ParameterValue="$OIDC_PROVIDER" \
      ParameterKey=OidcUrl,ParameterValue="$OIDC_URL" \
      ParameterKey=OidcThumbprints,ParameterValue=\"$OIDC_THUMBPRINTS\" \
      ParameterKey=OidcAudience,ParameterValue="$OIDC_AUDIENCE" \
    --tags \
      Key=Project,Value="$PROJECT" \
      Key=Repository,Value="$REPOSITORY" \
      Key=Environment,Value="$ENVIRONMENT" \
      Key=Owner,Value="$OWNER" \
      Key=AccountId,Value="$ACCOUNT_ID" \
      Key=Region,Value="$REGION" \
      Key=DeployedBy,Value="$DEPLOYED_BY" \
      Key=ManagedBy,Value="$MANAGED_BY" \
      Key=DeploymentID,Value="$DEPLOYMENT_ID" 2>&1) || {
    
    # Check if error is "No updates"
    if echo "$UPDATE_OUTPUT" | grep -q "No updates are to be performed"; then
      echo "✓ Stack already up to date (no changes detected)"
      echo ""
      echo "Step 6: Verifying deployment..."
      
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
        --query 'Stacks[0].Outputs[?OutputKey==`OidcProviderArn`].OutputValue' \
        --output text)

      echo "✓ Foundation deployment complete"
      echo ""
      echo "Resources created:"
      echo "  S3 State Bucket: $BUCKET"
      echo "  DynamoDB Lock Table: $TABLE"
      echo "  OIDC Provider: $OIDC_ARN"
      echo ""
      echo "Parameter Store entries created:"
      echo "  /terraform/foundation/s3-state-bucket"
      echo "  /terraform/foundation/dynamodb-lock-table"
      echo "  /terraform/foundation/oidc-provider"
      echo ""
      echo "Next steps:"
      echo "  Deploy terraform-aws-deployment-roles for IAM role management"
      echo ""
      exit 0
    else
      # Real error
      echo "✗ Stack update failed:"
      echo "$UPDATE_OUTPUT"
      exit 1
    fi
  }

  echo "✓ CloudFormation stack update initiated"
  echo "  Waiting for stack update to complete..."

  # Try to wait for update completion
  if aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" 2>&1; then
    echo "✓ Stack update completed successfully"
  else
    # Check what actually happened
    FINAL_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" \
      --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "UNKNOWN")

    case "$FINAL_STATUS" in
      UPDATE_COMPLETE)
        # Wait command can fail even if update completed - likely due to "No updates"
        echo "✓ Stack update completed (no changes detected)"
        ;;
      *COMPLETE)
        # Any other complete status (shouldn't happen but handle gracefully)
        echo "✓ Stack is in a complete state: $FINAL_STATUS"
        ;;
      *)
        # Actual failure
        echo "✗ Stack update failed with status: $FINAL_STATUS"
        echo "  Check CloudFormation console for details"
        exit 1
        ;;
    esac
  fi
fi

echo ""
echo "Step 6: Verifying deployment..."

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
  --query 'Stacks[0].Outputs[?OutputKey==`OidcProviderArn`].OutputValue' \
  --output text)

echo "✓ Foundation deployment complete"
echo ""
echo "Resources created:"
echo "  S3 State Bucket: $BUCKET"
echo "  DynamoDB Lock Table: $TABLE"
echo "  OIDC Provider: $OIDC_ARN"

echo ""
echo "Parameter Store entries created:"
echo "  /terraform/foundation/s3-state-bucket"
echo "  /terraform/foundation/dynamodb-lock-table"
echo "  /terraform/foundation/oidc-provider"
echo ""
echo "Next steps:"
echo "  Deploy terraform-aws-deployment-roles for IAM role management"
echo ""
