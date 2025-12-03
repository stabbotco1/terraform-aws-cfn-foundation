# terraform-aws-cfn-foundation

Part of the [AWS Terraform Foundation Suite](https://github.com/USERNAME/aws-terraform-foundation-suite)

## Purpose

Solves the chicken-and-egg problem of OpenTofu state management by using CloudFormation (which manages its own state) to create shared backend resources for the entire Terraform Foundation Suite.

## Resources Created

**1. S3 Bucket** - OpenTofu state storage

- Versioning enabled
- Encryption enabled (AWS KMS managed)
- Deletion protection
- Public access blocked
- Intelligent tiering lifecycle policy

**2. DynamoDB Table** - State locking

- Point-in-time recovery enabled
- Deletion protection
- Partition key: `LockID` (String)
- On-demand billing

**3. GitHub OIDC Provider** - Authentication

- Provider URL: `token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`
- Reuse if already exists (validated)

**4. Parameter Store Entries** - Configuration distribution

- `/terraform/foundation/s3-state-bucket`
- `/terraform/foundation/dynamodb-lock-table`
- `/terraform/foundation/oidc-github-provider`
- `/terraform/foundation/shared-modules-repository`

## Prerequisites

- AWS account with admin access
- AWS CLI configured and authenticated
- GitHub CLI installed and authenticated
- Bash 4+ (macOS: `brew install bash`)
- jq (for JSON processing in scripts)

### Verifying Prerequisites

Run the verification script to check if all prerequisites are satisfied:

```bash
./scripts/verify-prerequisites.sh
```

This script checks:

- AWS CLI and authentication
- GitHub CLI and authentication
- Required tools (jq, bash version)
- Required files (bootstrap.yaml)

## Quick Start

```bash
# Deploy foundation
./scripts/deploy.sh

# Verify deployment
./scripts/list-deployed-resources.sh
```

## CloudFormation Stack

- **Stack Name**: `terraform-shared-infrastructure`
- **Termination Protection**: Enabled
- **Stack Policy**: Prevent updates to critical resources

## Scripts

- `scripts/deploy.sh` - Deploy CloudFormation foundation (handles all stack states)
- `scripts/destroy.sh` - Destroy foundation (supports `--auto-approve` flag)
- `scripts/list-deployed-resources.sh` - List deployed resources (non-interactive)
- `scripts/verify-prerequisites.sh` - Validate prerequisites
- `scripts/release-version.sh` - Squash history and create version tag

### Script Features

**deploy.sh:**

- Handles `ROLLBACK_COMPLETE` (auto-cleanup and recreate)
- Handles `UPDATE_ROLLBACK_COMPLETE` (allows updates)
- Idempotent (safe to run multiple times)
- Interactive confirmation for updates

**destroy.sh:**

- Checks for dependent Project 3 resources
- Checks for state files in S3
- Cleans up orphaned resources from failed deployments
- Supports `--auto-approve` for automation
- Requires manual confirmation by default

**Usage:**

```bash
# Deploy (interactive)
./scripts/deploy.sh

# Destroy (interactive - requires typing confirmations)
./scripts/destroy.sh

# Destroy (automated - for scripts/CI)
./scripts/destroy.sh --auto-approve
```

## Git History Management

This project uses squashed git history to prevent sensitive data or unnecessary commits from being published.

### Automatic Squashing

A git hook (`.git/hooks/pre-push`) **automatically squashes** all commits into a single commit before pushing to GitHub. This ensures no development history is ever published to the remote repository.

**Behavior:**

- Detects multiple commits before push
- Automatically squashes to single commit
- Preserves the most recent commit message
- Proceeds with push automatically

**To bypass** (not recommended):

```bash
git push --no-verify
```

### Creating a Release

```bash
# During development - commit normally
git add .
git commit -m "Fix CloudFormation template"
git commit -m "Add bucket policy"
# ... many commits ...

# Push to remote (auto-squashes)
git push origin main

# Create version tag
git tag v1.0.0
git push origin v1.0.0
```

Alternatively, use the release script for manual control:

```bash
./scripts/release-version.sh v1.0.0
git push -f origin main
git push origin v1.0.0
```

### Version Pinning Strategy

- Use semantic versioning: `vMAJOR.MINOR.PATCH`
- Each release = single commit + version tag
- Consumers reference specific tags: `?ref=v1.0.0`
- Clean history prevents exposure of development artifacts

## Development Environment

This project is designed to work in your native macOS/Linux environment. All scripts and tools run directly on your host system with your existing AWS and GitHub authentication.

### Containerized Development (Lessons Learned)

Containerized development was explored but deferred due to practical considerations:

**Issues Encountered:**

- AWS CLI crashes in containers on macOS with Rosetta translation
- Error: `rosetta error: failed to open elf at /lib64/ld-linux-x86-64.so.2`
- Architecture compatibility issues (ARM/x86) with Podman on Apple Silicon
- Added complexity without clear immediate value for this use case

**Decision:**

- Native environment works reliably and meets all current needs
- Time better spent on actual infrastructure deployment
- Containerized development may be revisited in future with:
  - Native ARM-based container images
  - Resolved architecture compatibility
  - Clear value proposition for the workflow

**Dockerfile Retained:**

- The `Dockerfile` remains in the repository for reference
- Can be used for CI/CD pipelines or GitHub Actions
- May be useful for future containerized workflows

## Destruction Warning

⚠️ **CRITICAL**: This project must be destroyed LAST, after all other projects (2, 3, 4+) are destroyed. Foundation destruction deletes the state bucket used by all other projects.

### Destruction Dependency Chain

Each project checks only its immediate dependents, creating a chain of responsibility:

```
Project 4+ (Applications)
    ↓ blocks
Project 3 (deployment-roles) ← checks for downstream applications
    ↓ blocks
Project 1 (cfn-foundation) ← checks ONLY for Project 3
```

**This Project Checks For:**

1. **State files** in S3 bucket (any project using the shared backend)
2. **Resources tagged** with `Project=terraform-aws-deployment-roles`

If either check fails, destruction is blocked until Project 3 is destroyed first.

## Architecture

This is Project 1 in the four-tier architecture:

```
Project 1: CloudFormation Foundation (this project)
    ↓ creates
[Shared Resources: S3, DynamoDB, OIDC, Parameter Store]
    ↓ consumed by
Project 2: Shared Modules
    ↓ provides modules to
Project 3: Deployment Roles
    ↓ creates IAM roles for
Project 4+: Application Deployments
```

For complete architecture documentation, see the [AWS Terraform Foundation Suite](https://github.com/USERNAME/aws-terraform-foundation-suite).
