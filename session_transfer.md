# Session Transfer - Deploy/Destroy Script Robustness

## Current Situation

The deploy and destroy scripts are encountering corner cases that are not being handled gracefully. The scripts need to be made robust to handle unexpected states and failures.

## Current Problem

**Stack State:** `ROLLBACK_COMPLETE` (failed initial creation)
**Buckets:** Orphaned buckets exist from failed deployment:
- `terraform-state-694394480102-us-east-1`
- `terraform-state-logs-694394480102-us-east-1`

**Issue:** When deploy.sh runs and encounters ROLLBACK_COMPLETE, it attempts to clean up buckets and recreate the stack, but the cleanup logic is not working correctly, causing subsequent deployments to fail with "bucket already exists" errors.

## Task for New Agent

**Objective:** Fix deploy.sh and destroy.sh to gracefully handle all corner cases and unexpected states.

## Critical Constraints

1. **DO NOT read existing .md files** - They may contain outdated or incorrect information
2. **DO NOT create CHANGES.md or backup files** - No documentation files
3. **DO NOT use AWS SDK to modify/delete resources** - SDK can ONLY be used to query/confirm state
4. **ALL changes must be made through script modifications only**
5. **Read all non-.md project files first** - Use them as source of truth

## Required Approach

1. **Read these files to understand current state:**
   - `bootstrap.yaml` - CloudFormation template
   - `scripts/deploy.sh` - Deployment script
   - `scripts/destroy.sh` - Destruction script
   - `scripts/verify-prerequisites.sh` - Prerequisites checker
   - `.env` - Configuration
   - `.gitignore` - Ignored files

2. **Use AWS CLI (read-only) to confirm current state:**
   - Stack status: `aws cloudformation describe-stacks --stack-name terraform-shared-infrastructure`
   - Bucket existence: `aws s3 ls | grep terraform-state`
   - Stack resources: `aws cloudformation describe-stack-resources --stack-name terraform-shared-infrastructure`

3. **Identify corner cases that need handling:**
   - ROLLBACK_COMPLETE with orphaned buckets
   - Buckets exist but no stack
   - Stack exists but buckets don't
   - Partial resource creation
   - Failed imports
   - DynamoDB table with deletion protection
   - OIDC provider already exists
   - Any other failure states

4. **Fix scripts to handle these cases:**
   - Make deploy.sh idempotent (safe to run multiple times)
   - Make destroy.sh complete (cleans up all resources)
   - Add proper error detection and recovery
   - Add clear logging for each state transition
   - Ensure scripts can recover from any failure state

## Expected Outcomes

After fixes:
- `./scripts/deploy.sh` should work from ANY starting state (clean, partial, failed, etc.)
- `./scripts/destroy.sh` should completely clean up ALL resources
- Both scripts should be idempotent
- Both scripts should provide clear feedback about what they're doing
- No manual intervention should be required for recovery

## Testing Scenarios

The scripts should handle:
1. Fresh deployment (no stack, no buckets)
2. Redeployment (stack exists, buckets exist)
3. Failed deployment recovery (ROLLBACK_COMPLETE)
4. Orphaned resources (buckets exist, no stack)
5. Partial cleanup (some resources exist, some don't)
6. Multiple consecutive runs (idempotent)

## Current Script Locations

- Deploy: `/Users/stephenabbot/projects/terraform-aws-cfn-foundation/scripts/deploy.sh`
- Destroy: `/Users/stephenabbot/projects/terraform-aws-cfn-foundation/scripts/destroy.sh`
- Verify: `/Users/stephenabbot/projects/terraform-aws-cfn-foundation/scripts/verify-prerequisites.sh`

## AWS Account Context

- Account ID: `694394480102`
- Region: `us-east-1`
- Stack Name: `terraform-shared-infrastructure`
- State Bucket: `terraform-state-694394480102-us-east-1`
- Log Bucket: `terraform-state-logs-694394480102-us-east-1`
- DynamoDB Table: `terraform-locks-694394480102-us-east-1`

## Key Design Decisions Already Made

1. S3 buckets have `DeletionPolicy: Retain` (protected by default)
2. DynamoDB table has `DeletionPolicy: Delete` (always destroyed)
3. DynamoDB has runtime deletion protection (prevents console accidents)
4. OIDC provider auto-detected from git remote (GitHub, GitLab, Bitbucket)
5. Git state must be clean (no uncommitted/unpushed changes)
6. Bucket retention is optional in destroy (user prompted)
7. No prompts in deploy (fully automated when prerequisites pass)

## Success Criteria

Scripts are considered fixed when:
1. Deploy works from current ROLLBACK_COMPLETE state without manual intervention
2. Deploy can be run multiple times without errors
3. Destroy completely cleans up all resources
4. Destroy can be run multiple times without errors
5. All corner cases are handled with clear error messages
6. No manual AWS CLI commands are needed for recovery

## Start Here

1. Read all project files (except .md files)
2. Query AWS to understand current state
3. Identify gaps in error handling
4. Fix scripts systematically
5. Test each scenario mentally/logically
6. Ensure idempotency throughout
