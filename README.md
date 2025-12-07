# Terraform AWS CloudFormation Foundation

**Author:** Stephen Abbot  
**Repository:** <https://github.com/stabbotco1/terraform-aws-cfn-foundation>
**License:** MIT

Bootstrap infrastructure for Terraform state management using AWS CloudFormation.

## Table of Contents

- [Problem Statement](#problem-statement)
- [Purpose](#purpose)
- [Resources Deployed](#resources-deployed)
- [Quick Start](#quick-start)
- [Notable Features](#notable-features)
- [Scripts](#scripts)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Project Tags](#project-tags)

## Problem Statement

Terraform requires S3 and DynamoDB for remote state management, but you cannot use Terraform to create these resources without already having a place to store state. This creates a chicken-and-egg problem for infrastructure bootstrapping.

This project solves this by using CloudFormation (which manages its own state) to create the foundational resources needed for all subsequent Terraform deployments.

## Purpose

This project deploys and manages account-level shared infrastructure using idempotent scripts that:

- Handle happy path deployments and reasonable corner cases
- Minimize drift through consistent naming and tagging patterns
- Detect and report orphaned resources
- Enable high-confidence inventory and management of deployed resources
- Provide verification of prerequisites before deployment

## Resources Deployed

### Core Resources

| Resource | Name Pattern | Purpose |
|----------|-------------|---------|
| S3 Bucket | `terraform-state-{account-id}-{region}` | Terraform state storage with versioning |
| S3 Bucket | `terraform-state-logs-{account-id}-{region}` | Access logs for state bucket |
| DynamoDB Table | `terraform-locks-{account-id}-{region}` | State locking to prevent concurrent runs |
| OIDC Provider | Auto-detected from git remote | CI/CD authentication without credentials |
| SSM Parameters | `/terraform/foundation/*` | Configuration distribution to other projects |

### Resource Properties

**S3 State Bucket:**

- Versioning enabled for state history
- AES256 encryption (AWS-managed keys)
- Intelligent tiering for cost optimization
- Private access only
- Retained on stack deletion (DeletionPolicy: Retain)

**DynamoDB Lock Table:**

- On-demand billing (pay per use)
- Point-in-time recovery enabled
- Deletion protection enabled
- Deleted with stack (DeletionPolicy: Delete)

**OIDC Provider:**

- Auto-detected from GitHub, GitLab, or Bitbucket
- Enables secure CI/CD without long-lived credentials

## Quick Start

### Prerequisites

- AWS account with administrative access
- AWS CLI installed and configured
- GitHub CLI installed and authenticated
- jq, openssl, bash 4+
- Git repository with clean state

### Verify Prerequisites

```bash
./scripts/verify-prerequisites.sh
```

### Deploy

```bash
./scripts/deploy.sh
```

The script handles:

- Fresh deployments (no existing resources)
- Updates to existing stack
- "No updates" scenarios (idempotent)
- Failed stack recovery (ROLLBACK_COMPLETE)

### List Deployed Resources

```bash
./scripts/list-deployed-resources.sh
```

Shows stack status, resource details, and orphaned resources.

### Destroy

```bash
./scripts/destroy.sh
```

Interactive destruction with safety prompts for stack and bucket deletion.

## Notable Features

### Idempotent Deployment

- `deploy.sh` can be run multiple times safely
- Handles "No updates" gracefully without errors
- Detects and recovers from failed states

### Orphan Detection

- `list-deployed-resources.sh` identifies resources with project tags not managed by stack
- Uses multiple detection methods: naming patterns, tags, existence checks
- Reports orphans without suggesting actions (informational only)

### Testing Infrastructure

- `TESTING_FORCE_STACK_UPDATE` flag in `.env` enables forced stack updates
- Adds timestamp parameter to force updates for testing scenarios
- Disabled by default (production-safe)

### Stack Protection

- Termination protection enabled on deployment
- Prevents accidental deletion
- Automatically disabled by destroy script

### OIDC Provider Auto-Detection

Automatically detects and configures OIDC provider from git remote:

- **GitHub**: `token.actions.githubusercontent.com`
- **GitLab**: `gitlab.com`
- **Bitbucket**: `api.bitbucket.org/2.0/workspaces/{workspace}/pipelines-config/identity/oidc`

## Scripts

### verify-prerequisites.sh

Validates environment before deployment:

- Git repository state (clean, pushed, on branch)
- AWS CLI and authentication
- Required tools (jq, openssl, gh CLI)
- AWS permissions (CloudFormation, IAM, S3, DynamoDB, SSM)

Exit codes: 0 (success), 1 (failure with details)

### deploy.sh

Idempotent deployment script:

**Handles:**

- Fresh deployment (no stack, no resources)
- Stack updates (existing stack)
- No changes (graceful exit)
- ROLLBACK_COMPLETE recovery (cleanup and recreate)
- Orphaned bucket detection

**Features:**

- Automatic OIDC provider detection
- Termination protection management
- Versioned bucket handling
- Parameter store updates

### list-deployed-resources.sh

Non-interactive resource inventory:

**Shows:**

- CloudFormation stack status and metadata
- S3 bucket details (versioning, encryption, object counts)
- DynamoDB table details (status, billing, active locks)
- OIDC provider details (thumbprint, audience)
- SSM parameter values
- Orphaned resources (not managed by stack)

### destroy.sh

Safe destruction with confirmations:

**Requires:**

- Type `DESTROY` to confirm stack deletion
- Type `DELETE BUCKETS` to destroy S3 buckets (or Enter to retain)

**Features:**

- Early exit if no resources exist
- Orphaned bucket detection and cleanup
- DynamoDB deletion protection disable
- Versioned bucket emptying
- Bucket retention option

## Configuration

### Environment Variables (.env)

```bash
# Testing Configuration
# WARNING: Only enable for testing - forces unnecessary stack updates
TESTING_FORCE_STACK_UPDATE=false

# AWS Configuration
AWS_REGION=us-east-1

# Resource Tags
TAG_ENVIRONMENT=Production
TAG_OWNER=YourName
TAG_MANAGED_BY=CloudFormation
TAG_DEPLOYMENT_ID=Default
```

**Important:** Values with spaces need quotes:

```bash
TAG_OWNER="John Doe"  # Correct
TAG_OWNER=John Doe    # Wrong - will truncate to "John"
```

### Testing Mode

To enable forced stack updates for testing:

1. Set `TESTING_FORCE_STACK_UPDATE=true` in `.env`
2. Run `./scripts/deploy.sh`
3. Stack will update even with no changes (timestamp parameter changes)

**Note:** This is for testing only. Do not use in production.

## Troubleshooting

### Stack in ROLLBACK_COMPLETE

**Cause:** Initial stack creation failed

**Solution:** Run `./scripts/deploy.sh` - automatically cleans up and recreates

### "No updates are to be performed"

**Cause:** No changes detected between current and desired state

**Solution:** This is normal - stack is already in desired state

### Stack Operation In Progress

**Cause:** Another CloudFormation operation is running

**Solution:** Wait for current operation to complete, then retry

### Orphaned Resources Detected

**Cause:** Resources exist with project tags but not managed by stack

**Solution:** Review output of `./scripts/list-deployed-resources.sh` to identify orphans

### Prerequisites Check Failed

**Cause:** Missing tools or permissions

**Solution:**

1. Review output of `./scripts/verify-prerequisites.sh`
2. Install missing tools
3. Configure AWS credentials with sufficient permissions
4. Clean git state (commit/push changes)

### OIDC Provider Already Exists

**Cause:** OIDC provider with same URL already exists in account (from previous deployment or another project)

**Solution:**

1. Check existing providers: `aws iam list-open-id-connect-providers`
2. Either delete existing provider or skip this deployment
3. Note: Only one OIDC provider per URL allowed per account

**Limitation:** Deploy script does not check for existing OIDC providers before stack creation

### Investigation Commands

```bash
# Check stack status
aws cloudformation describe-stacks --stack-name terraform-shared-infrastructure

# List stack resources
aws cloudformation describe-stack-resources --stack-name terraform-shared-infrastructure

# Check stack events
aws cloudformation describe-stack-events --stack-name terraform-shared-infrastructure --max-items 20

# Verify S3 buckets
aws s3 ls | grep terraform-state

# Check DynamoDB table
aws dynamodb describe-table --table-name terraform-locks-$(aws sts get-caller-identity --query Account --output text)-us-east-1

# Verify OIDC provider
aws iam list-open-id-connect-providers
```

## Project Tags

`#aws` `#terraform` `#cloudformation` `#foundation` `#core` `#iac` `#infrastructure` `#bootstrap` `#state-management` `#remote-state` `#s3-backend` `#dynamodb-locking` `#oidc` `#cicd` `#devops` `#ai-assisted` `#ai-generated` `#llm-assisted` `#ai-pair-programming` `#agentic-ai` `#ai-infrastructure` `#ai-devops`
