# Terraform AWS CloudFormation Foundation

Bootstrap infrastructure for Terraform/OpenTofu state management using AWS CloudFormation.

## Notable Features

- Handles orphaned bucket import/cleanup
- OIDC provider auto-detection from git remote
- Versioned bucket deletion support
- Stack state recovery (ROLLBACK_COMPLETE handling)
- Termination protection management

## Purpose

Solves the chicken-and-egg problem of Terraform state management: Terraform needs S3 and DynamoDB for remote state, but you can't use Terraform to create those resources without already having a place to store state. This project uses CloudFormation (which manages its own state) to create the foundational resources needed for all subsequent Terraform/OpenTofu deployments.

This is designed as the **first project** in a multi-project infrastructure setup, providing shared backend resources that all other Terraform projects will consume.

## What This Project Creates

### Core Resources

**1. S3 State Bucket** (`terraform-state-{account-id}-{region}`)

- Versioning enabled for state history
- AES256 encryption (AWS-managed keys)
- Intelligent tiering for cost optimization
- Private access only (public access blocked)
- Logging to dedicated log bucket
- Retained on stack deletion (DeletionPolicy: Retain)

**2. S3 Log Bucket** (`terraform-state-logs-{account-id}-{region}`)

- Stores access logs from state bucket
- AES256 encryption
- 90-day log expiration
- Private access only
- Retained on stack deletion

**3. DynamoDB Lock Table** (`terraform-locks-{account-id}-{region}`)

- Prevents concurrent Terraform runs
- Point-in-time recovery enabled
- On-demand billing (pay per use)
- Deletion protection enabled
- Deleted with stack (DeletionPolicy: Delete)

**4. OIDC Provider**

- Auto-detected from git remote (GitHub, GitLab, or Bitbucket)
- Enables CI/CD authentication without long-lived credentials
- Used by subsequent deployment role projects

**5. SSM Parameters** (for configuration distribution)

- `/terraform/foundation/s3-state-bucket` - State bucket name
- `/terraform/foundation/dynamodb-lock-table` - Lock table name
- `/terraform/foundation/oidc-provider` - OIDC provider ARN

### Optional Resources

**6. CloudTrail** (when `FEATURE_CLOUDTRAIL_ENABLED=true` in `.env`)

- S3 CloudTrail Bucket (`cloudtrail-logs-{account-id}-{region}`)
- CloudTrail trail tracking all management events
- Multi-region trail (captures IAM/STS events globally)
- Intelligent tiering storage class
- 90-day log expiration
- Used for IAM Access Analyzer to create least-privilege policies

## Quick Start

### Prerequisites

- AWS account with administrative access
- AWS CLI installed and configured (`aws configure`)
- GitHub CLI installed and authenticated (`gh auth login`)
- jq installed (`brew install jq` on macOS)
- Bash 4+ recommended (`brew install bash` on macOS)
- Git repository with clean state (no uncommitted changes)

### Verify Prerequisites

```bash
./scripts/verify-prerequisites.sh
```

This checks:

- Git repository state (clean, pushed, on branch)
- AWS CLI and authentication
- Required tools (jq, openssl, gh)
- AWS permissions (CloudFormation, IAM, S3, DynamoDB, SSM)

### Deploy

```bash
./scripts/deploy.sh
```

The deployment script:

1. Verifies all prerequisites
2. Detects OIDC provider from git remote
3. Collects metadata from `.env` and AWS
4. Checks for existing stack or orphaned resources
5. Creates or updates CloudFormation stack
6. Enables termination protection
7. Outputs created resource names

**First deployment:** Creates all resources from scratch

**Subsequent deployments:** Updates existing stack with any changes

**Failed deployment recovery:** Automatically cleans up and recreates

### Verify Deployment

```bash
./scripts/list-deployed-resources.sh
```

Shows detailed information about all deployed resources including bucket contents, DynamoDB status, OIDC provider details, and CloudTrail status.

### Destroy

```bash
./scripts/destroy.sh
```

Interactive destruction with safety prompts:

1. Confirms destruction intent (type `DESTROY`)
2. Asks about S3 bucket deletion (type `DELETE BUCKETS` to destroy, or Enter to retain)
3. Empties buckets (if requested)
4. Deletes CloudFormation stack
5. Removes retained buckets (if requested)

**Important:** S3 buckets are retained by default to protect Terraform state. Only delete buckets if you're certain all dependent infrastructure has been destroyed.

## Configuration

### Environment Variables (.env)

Create a `.env` file in the project root (already gitignored):

```bash
# Feature Configuration
FEATURE_CLOUDTRAIL_ENABLED=true

# AWS Configuration
AWS_REGION=us-east-1

# Resource Tags
TAG_ENVIRONMENT=Production
TAG_OWNER=YourName
TAG_MANAGED_BY=CloudFormation
TAG_DEPLOYMENT_ID=Default
```

**Important:** Values with spaces need quotes in `.env`:

```bash
TAG_OWNER="John Doe"  # Correct
TAG_OWNER=John Doe    # Wrong - will truncate to "John"
```

### OIDC Provider Support

The project automatically detects your OIDC provider from the git remote URL:

**GitHub** (primary support)

- Detected from: `github.com` in remote URL
- Provider URL: `https://token.actions.githubusercontent.com`
- Uses known thumbprints for reliability

**GitLab** (community support)

- Detected from: `gitlab.com` in remote URL
- Provider URL: `https://gitlab.com`
- Thumbprint calculated dynamically

**Bitbucket** (community support)

- Detected from: `bitbucket.org` in remote URL
- Provider URL: `https://api.bitbucket.org/2.0/workspaces/{workspace}/pipelines-config/identity/oidc`
- Uses known thumbprint

### CloudTrail Configuration

CloudTrail is controlled by the `FEATURE_CLOUDTRAIL_ENABLED` parameter in `.env`:

**Enabled** (`FEATURE_CLOUDTRAIL_ENABLED=true`):

- Creates CloudTrail S3 bucket
- Creates CloudTrail trail tracking all management events
- Logs all AWS API calls (IAM, STS, CloudFormation, etc.)
- Use with IAM Access Analyzer to create least-privilege policies

**Disabled** (`FEATURE_CLOUDTRAIL_ENABLED=false`):

- Removes CloudTrail trail (stops logging)
- Retains CloudTrail S3 bucket with existing logs
- Can be re-enabled later (bucket will be imported)

**Toggling CloudTrail:**

1. Change `FEATURE_CLOUDTRAIL_ENABLED` in `.env`
2. Run `./scripts/deploy.sh`
3. Stack updates to enable/disable CloudTrail
4. Bucket is preserved through enable/disable cycles

## Resources Created (Detailed)

### S3 Buckets

| Bucket | Purpose | Versioning | Lifecycle | Deletion Policy |
|--------|---------|------------|-----------|-----------------|
| `terraform-state-*` | Terraform state files | Enabled | Intelligent tiering | Retain |
| `terraform-state-logs-*` | S3 access logs | Disabled | 90-day expiration | Retain |
| `cloudtrail-logs-*` | CloudTrail logs | Disabled | 90-day expiration, intelligent tiering | Retain (conditional) |

All buckets:

- Private only (PublicAccessBlockConfiguration)
- AES256 encryption (AWS-managed)
- Tagged with project metadata

### DynamoDB Table

**Table:** `terraform-locks-{account-id}-{region}`

Attributes:

- Partition key: `LockID` (String)
- Billing: On-demand (PAY_PER_REQUEST)
- Point-in-time recovery: Enabled
- Deletion protection: Enabled (runtime)
- Stack deletion: Deletes with stack

### CloudFormation Stack

**Stack Name:** `terraform-shared-infrastructure`

Stack features:

- Termination protection: Enabled
- Rollback: Automatic on failure
- Updates: Change sets for preview
- Exports: Stack outputs available cross-stack

### Stack Outputs

The stack exports these values for use by other CloudFormation stacks:

- `TerraformStateBucket` - S3 bucket name
- `TerraformLockTable` - DynamoDB table name
- `OidcProviderArn` - OIDC provider ARN
- `StackName` - CloudFormation stack name

## Scripts

### deploy.sh

Idempotent deployment script that handles all stack states:

**Features:**

- Automatic stack status detection
- ROLLBACK_COMPLETE recovery (auto-cleanup and recreate)
- Orphaned resource detection and import
- CloudTrail bucket lifecycle management
- OIDC provider cleanup on failure
- Versioned bucket deletion support

**Handles these scenarios:**

- Fresh deployment (no stack, no resources)
- Stack exists (performs update)
- Stack in ROLLBACK_COMPLETE (cleans up and recreates)
- Orphaned buckets (offers import or delete)
- Stack operation in progress (exits with error)
- No changes to deploy (gracefully completes)

### destroy.sh

Safe destruction script with confirmations:

**Features:**

- Early exit if no resources exist
- Orphaned bucket detection and cleanup
- DynamoDB deletion protection disable
- Versioned bucket emptying
- Bucket retention option
- Failed resource reporting

**Requires:**

- Type `DESTROY` to confirm stack deletion
- Type `DELETE BUCKETS` to destroy S3 buckets (or Enter to retain)

### verify-prerequisites.sh

Comprehensive prerequisite checker:

**Checks:**

- Git repository state (clean, pushed, on branch)
- AWS CLI and authentication
- AWS permissions (CloudFormation, IAM, S3, DynamoDB, SSM)
- Required tools (jq, openssl, gh CLI)
- Required files (bootstrap.yaml)

**Exit codes:**

- `0` - All prerequisites satisfied
- `1` - One or more failures (details printed)

### list-deployed-resources.sh

Non-interactive resource listing:

**Shows:**

- CloudFormation stack status and metadata
- S3 bucket details (versioning, encryption, object counts)
- DynamoDB table details (status, billing, active locks)
- OIDC provider details (thumbprint, audience)
- CloudTrail status (enabled/disabled, log counts)
- SSM parameter values

## Next Steps

After deploying this foundation:

1. **Deploy terraform-aws-deployment-roles**
   - Creates IAM roles for Terraform deployments
   - Uses OIDC provider from this project
   - Enables secure CI/CD without credentials
   - Centralized role management

2. **Configure Terraform Backend**

   ```hcl
   terraform {
     backend "s3" {
       bucket         = "terraform-state-<account-id>-<region>"
       key            = "project-name/terraform.tfstate"
       region         = "us-east-1"
       encrypt        = true
       dynamodb_table = "terraform-locks-<account-id>-<region>"
     }
   }
   ```

3. **Use SSM Parameters in Terraform**

   ```hcl
   data "aws_ssm_parameter" "state_bucket" {
     name = "/terraform/foundation/s3-state-bucket"
   }

   data "aws_ssm_parameter" "lock_table" {
     name = "/terraform/foundation/dynamodb-lock-table"
   }

   data "aws_ssm_parameter" "oidc_provider" {
     name = "/terraform/foundation/oidc-provider"
   }
   ```

## Troubleshooting

### Stack in ROLLBACK_COMPLETE

**Cause:** Initial stack creation failed

**Solution:** Run `./scripts/deploy.sh` - it will automatically:

1. Clean up orphaned resources (buckets, OIDC provider)
2. Delete the failed stack
3. Create a new stack

### Orphaned Buckets Detected

**Cause:** Stack was deleted but S3 buckets were retained

**Options:**

1. **Import:** Preserves existing state/logs (recommended)
2. **Delete:** Destroys all state/logs (use with caution)

The deploy script will prompt you to choose.

### "No updates are to be performed"

**Cause:** No changes detected between current and desired state

**Solution:** This is normal - the stack is already in the desired state

### Stack Operation In Progress

**Cause:** Another CloudFormation operation is running

**Solution:** Wait for the current operation to complete, then retry

### DELETE_FAILED State

**Cause:** CloudFormation couldn't delete some resources

**Solution:**

1. Check failed resources: `aws cloudformation describe-stack-resources --stack-name terraform-shared-infrastructure`
2. Manually delete stuck resources
3. Run `./scripts/destroy.sh` again

### Prerequisites Check Failed

**Cause:** Missing tools or permissions

**Solution:**

1. Review output of `./scripts/verify-prerequisites.sh`
2. Install missing tools
3. Configure AWS credentials with sufficient permissions
4. Clean git state (commit/push changes)

### Import Failed

**Cause:** Bucket configuration doesn't match template

**Solution:**

1. Check bucket settings match template requirements
2. Or delete buckets and create fresh: `./scripts/destroy.sh` → answer 'N' to import

## Investigation Tools

### Check Current Stack Status

```bash
aws cloudformation describe-stacks --stack-name terraform-shared-infrastructure --query 'Stacks[0].StackStatus' --output text
```

### List Stack Resources

```bash
aws cloudformation describe-stack-resources --stack-name terraform-shared-infrastructure --output table
```

### Check Stack Events

```bash
aws cloudformation describe-stack-events --stack-name terraform-shared-infrastructure --max-items 20 --output table
```

### Verify S3 Buckets

```bash
aws s3 ls | grep terraform-state
aws s3 ls | grep cloudtrail-logs
```

### Check DynamoDB Table

```bash
aws dynamodb describe-table --table-name terraform-locks-$(aws sts get-caller-identity --query Account --output text)-us-east-1
```

### Verify OIDC Provider

```bash
aws iam list-open-id-connect-providers
```

### Check CloudTrail Status

```bash
aws cloudtrail get-trail-status --name terraform-foundation-$(aws sts get-caller-identity --query Account --output text)
```

## Architecture Notes

### Why CloudFormation?

CloudFormation is used specifically to solve the bootstrap problem:

- CloudFormation manages its own state (no S3/DynamoDB needed)
- Creates the S3/DynamoDB resources that Terraform needs
- One-time setup, then use Terraform for everything else

### S3 Bucket Retention

Buckets have `DeletionPolicy: Retain` because:

- Protects against accidental state loss
- Allows stack deletion without data loss
- Enables stack recreation with existing state (import)
- Can be manually deleted when truly no longer needed

### DynamoDB Deletion Policy

Table has `DeletionPolicy: Delete` because:

- Lock table contains no persistent data (only active locks)
- Active locks are transient and short-lived
- Recreating table is safe and has no data loss risk
- Reduces cleanup burden

### Git State Requirements

Prerequisites check enforces clean git state because:

- Ensures deployment metadata is accurate
- Repository URL used for OIDC provider detection
- Tags and metadata derived from git state
- Prevents deployment of uncommitted/experimental changes

### Multi-Region Support

While resources are region-specific, CloudTrail is multi-region:

- IAM and STS are global services (us-east-1)
- Multi-region trail captures these events regardless of where they occur
- Important for IAM Access Analyzer to see all role usage

## License

MIT License - Copyright (c) 2025 Stephen Abbot

See LICENSE file for full details.
