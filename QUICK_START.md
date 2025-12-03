# Quick Start Guide

This guide will help you deploy the CloudFormation foundation in under 10 minutes.

## Prerequisites

1. **AWS Account** with admin access
2. **AWS CLI** configured with credentials
3. **Bash 4+** (macOS: `brew install bash`)
4. **GitHub CLI** (optional, for repository detection)

## Deployment Steps

```bash
# 1. Clone the repository
git clone https://github.com/USERNAME/terraform-aws-cfn-foundation.git
cd terraform-aws-cfn-foundation

# 2. Verify prerequisites
./scripts/verify-prerequisites.sh

# 3. Deploy foundation
./scripts/deploy.sh

# 4. Verify deployment
./scripts/list-deployed-resources.sh
```

## What Gets Created

- **S3 Bucket**: `terraform-state-{account-id}-{region}`
- **DynamoDB Table**: `terraform-locks-{account-id}-{region}`
- **GitHub OIDC Provider**: For GitHub Actions authentication
- **Parameter Store Entries**: Configuration for other projects

## Next Steps

After successful deployment:

1. **Deploy Project 2**: [terraform-aws-shared-modules](https://github.com/USERNAME/terraform-aws-shared-modules)
2. **Deploy Project 3**: [terraform-aws-deployment-roles](https://github.com/USERNAME/terraform-aws-deployment-roles)
3. **Deploy Applications**: Any Project 4+ application deployments

## Git History Protection

This project automatically squashes git history before pushing to prevent sensitive data exposure:

- **Automatic**: Pre-push hook squashes all commits to single commit
- **Transparent**: Happens automatically on every `git push`
- **Safe**: Remote repository never sees development history

Commit normally during development - the hook handles squashing automatically.

## Troubleshooting

### Common Issues

**Error: "Stack in ROLLBACK_COMPLETE state"**
- The deploy script automatically handles this
- Failed stack will be cleaned up and recreated
- No manual intervention needed

**Error: "Stack already exists"**
- The script will offer to update the existing stack
- Choose "yes" to update or "no" to cancel

**Error: "Access Denied"**
- Ensure your AWS credentials have admin permissions
- Check: `aws sts get-caller-identity`

**Error: "OIDC provider already exists"**
- This is normal and expected
- The script will reuse the existing provider

**Error: "Bash version incompatible"**
- Install Bash 4+: `brew install bash` (macOS)
- Restart your terminal after installation

**Stack Deployment Failed:**
- Run `./scripts/destroy.sh` to clean up
- Script will remove orphaned resources automatically
- Then run `./scripts/deploy.sh` again

### Getting Help

1. Check the [Architecture Documentation](https://github.com/USERNAME/aws-terraform-foundation-suite)
2. Run `./scripts/verify-prerequisites.sh` for detailed diagnostics
3. Use `./scripts/list-deployed-resources.sh` to check current state

## Destruction Warning

⚠️ **DANGER**: Only destroy this foundation AFTER destroying all dependent projects (2, 3, 4+).

```bash
# Interactive mode (requires confirmations)
./scripts/destroy.sh

# Automated mode (for scripts/CI)
./scripts/destroy.sh --auto-approve
```

**What the destroy script checks:**
- Resources from Project 3 (deployment-roles)
- State files in S3 bucket
- Cleans up orphaned resources from failed deployments

This will permanently delete all Terraform state files and make dependent projects unmanageable.