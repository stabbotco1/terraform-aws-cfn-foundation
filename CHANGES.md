# Changes Summary

## Overview
This document summarizes the changes made to implement improved S3 bucket lifecycle management, git state validation, and enhanced tagging.

## Files Modified

### 1. `.env`
**Changes:**
- Restructured with `FEATURE_` and `TAG_` prefixes for clarity
- Added `FEATURE_CLOUDTRAIL_ENABLED` for CloudTrail configuration
- Changed `Region` to `AWS_REGION` for AWS convention compliance
- Removed `TAG_PROJECT` (now derived from git remote)

**New Structure:**
```bash
# Feature Configuration
FEATURE_CLOUDTRAIL_ENABLED=true

# AWS Configuration
AWS_REGION=us-east-1

# Resource Tags
TAG_ENVIRONMENT=Production
TAG_OWNER=StephenAbbot
TAG_MANAGED_BY=CloudFormation
TAG_DEPLOYMENT_ID=Default
```

### 2. `bootstrap.yaml`
**Changes:**
- **Removed:** `OidcAction` parameter (always auto-detect now)
- **Added:** `Repository` parameter for full git URL
- **Added:** `Repository` tag to all resources
- **Changed:** DynamoDB `DeletionPolicy` from `Retain` to `Delete`
- **Removed:** `IAMOIDCProviderGitHub` resource (OIDC must exist externally)
- **Updated:** SSM parameter for OIDC to always use ARN format
- **Updated:** All resource tags to include comprehensive metadata

**Key Behavior Changes:**
- S3 buckets: `DeletionPolicy: Retain` (protected by default)
- DynamoDB table: `DeletionPolicy: Delete` (always destroyed with stack)
- DynamoDB table: `DeletionProtectionEnabled: true` (prevents console accidents)
- OIDC provider: Must exist before deployment (deploy.sh validates)

### 3. `scripts/verify-prerequisites.sh`
**Changes:**
- **Added:** Color-coded output (green ✓, red ✗, yellow ⚠)
- **Added:** Git state validation checks:
  - Inside git repository
  - No uncommitted changes
  - No untracked files
  - Not in detached HEAD state
  - Branch has upstream configured
  - No unpushed commits
- **Updated:** All check functions with color output
- **Updated:** Check execution order (git checks first)

**New Behavior:**
- Collects all failures before exiting
- Returns exit code 1 if any check fails
- Visual indicators for pass/fail status

### 4. `scripts/deploy.sh`
**Changes:**
- **Added:** Call to `verify-prerequisites.sh` at start
- **Added:** Repository URL extraction (normalized to HTTPS, keeps .git)
- **Added:** Project name extraction (removes .git)
- **Added:** `Repository` tag alongside `Project` tag
- **Added:** Orphaned bucket detection and auto-import logic
- **Added:** CloudTrail configuration from `.env`
- **Removed:** OIDC creation logic (now validates existing only)
- **Updated:** Parameter passing to include `Repository`
- **Updated:** Region sourcing from `AWS_REGION` in `.env`

**New Features:**
- **Auto-import:** Detects orphaned S3 buckets from previous deployments
- **Smart detection:** Handles buckets in three states: none, in-stack, orphaned
- **Import process:** Creates import changeset, executes, waits for completion
- **OIDC validation:** Checks thumbprint and audience of existing provider

### 5. `scripts/destroy.sh`
**Changes:**
- **Added:** Call to `verify-prerequisites.sh` at start
- **Updated:** Bucket deletion prompt to "Type 'DELETE BUCKETS' to destroy buckets (or press Enter to retain)"
- **Added:** Clear messaging about DynamoDB always being deleted
- **Added:** Orphaned bucket cleanup when stack doesn't exist
- **Updated:** Final summary to indicate retained vs deleted resources

**New Behavior:**
- Two-step confirmation: DESTROY (stack) → DELETE BUCKETS (optional)
- DynamoDB table always deleted (no prompt needed)
- S3 buckets retained by default unless explicitly confirmed
- Provides guidance for redeployment after retention

## Behavioral Changes

### S3 Bucket Lifecycle
1. **First deploy:** Creates buckets, stack owns them
2. **Destroy (retain):** Stack deleted, buckets orphaned
3. **Second deploy:** Auto-detects orphaned buckets, imports them into new stack
4. **Destroy (delete):** Empties and deletes buckets completely

### DynamoDB Table Lifecycle
1. **Deploy:** Creates table with deletion protection enabled
2. **Destroy:** Removes protection, deletes table (always)
3. **Redeploy:** Creates new table (no import needed)

### Git State Enforcement
- **Deploy:** Blocked if uncommitted changes, untracked files, or unpushed commits
- **Destroy:** Same git state checks applied
- **Verify:** Can be run standalone to check prerequisites

### OIDC Provider
- **Must exist before deployment**
- **Deploy script validates:** Thumbprint and audience
- **No longer created by CloudFormation**
- **SSM parameter stores ARN format**

## Tag Structure

All resources now include:
- `Project`: Short name (e.g., "terraform-aws-cfn-foundation")
- `Repository`: Full URL (e.g., "https://github.com/USERNAME/terraform-aws-cfn-foundation.git")
- `Environment`: From TAG_ENVIRONMENT
- `Owner`: From TAG_OWNER
- `AccountId`: AWS Account ID
- `Region`: AWS Region
- `DeployedBy`: IAM principal ARN
- `ManagedBy`: From TAG_MANAGED_BY
- `DeploymentID`: From TAG_DEPLOYMENT_ID

## Migration Notes

### For Existing Deployments
If you have an existing deployment:

1. **Update .env file** with new structure
2. **Run verify-prerequisites.sh** to ensure git state is clean
3. **Run deploy.sh** - it will update the stack with new parameters
4. **Note:** Existing OIDC provider will be validated (not recreated)

### For New Deployments
1. **Create OIDC provider manually** (if not exists):
   ```bash
   aws iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com \
     --client-id-list sts.amazonaws.com \
     --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
   ```
2. **Configure .env file** with your values
3. **Ensure git state is clean** (committed and pushed)
4. **Run deploy.sh**

## Testing Recommendations

1. **Test git state checks:**
   ```bash
   # Should fail
   touch test.txt
   ./scripts/deploy.sh
   
   # Should pass
   rm test.txt
   ./scripts/deploy.sh
   ```

2. **Test bucket retention:**
   ```bash
   ./scripts/deploy.sh
   ./scripts/destroy.sh  # Press Enter at bucket prompt
   ./scripts/deploy.sh   # Should auto-import buckets
   ```

3. **Test bucket deletion:**
   ```bash
   ./scripts/deploy.sh
   ./scripts/destroy.sh  # Type "DELETE BUCKETS"
   # Verify buckets are gone
   ```

## Breaking Changes

1. **OIDC provider must exist** - deploy.sh will fail if not found
2. **Git state must be clean** - uncommitted/unpushed changes block deployment
3. **.env file structure changed** - must update variable names
4. **DynamoDB always deleted** - no longer retained on stack deletion

## Benefits

1. **Safer deployments:** Git state validation prevents drift
2. **Cleaner redeployments:** Auto-import handles orphaned buckets
3. **Better traceability:** Repository URL in tags
4. **Clearer configuration:** FEATURE_ vs TAG_ prefixes
5. **Consistent behavior:** DynamoDB lifecycle matches its transient nature
6. **User-friendly:** Clear prompts and colored output
