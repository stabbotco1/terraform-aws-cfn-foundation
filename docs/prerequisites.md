# Prerequisites

## Required Tools

- AWS CLI version 2.x for AWS service interaction and authentication
- Bash version 4.x or higher for script execution
- jq for JSON processing in deployment scripts
- Git for repository information detection and version control

## AWS Account Requirements

- IAM permissions to create CloudFormation stacks, S3 buckets, DynamoDB tables, OIDC providers, IAM roles, and SSM parameters
- No existing resources with conflicting names in the target region
- Account must not have reached service quotas for S3 buckets or DynamoDB tables

The deployment uses your current AWS credentials from the AWS CLI configuration. No specific IAM role is required for initial foundation deployment.

## Configuration Setup

Before deployment, you must configure your AWS account ID:

1. Copy the environment template:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` and replace the placeholder with your actual AWS account ID:
   ```bash
   AWS_ACCOUNT_ID=your-actual-account-id
   ```

The verification script will ensure your `.env` configuration matches your current AWS session.

## Git Repository Setup

The repository must be:

- Initialized as a git repository with a remote origin configured
- Remote origin must be GitHub, GitLab, or Bitbucket for OIDC provider configuration
- Working directory must be clean with no uncommitted changes or untracked files
- All commits must be pushed to the remote repository

These requirements ensure deployment metadata is accurate and prevent deploying from inconsistent repository states.
