# Terraform AWS CloudFormation Foundation

https://github.com/stephenabbot/terraform-aws-cfn-foundation

Shared backend infrastructure for Terraform and OpenTofu projects using CloudFormation for bootstrapping.

## Table of Contents

- [Why](#why)
- [How](#how)
  - [Architecture](#architecture)
  - [Script-Based Deployment](#script-based-deployment)
- [Resources Deployed](#resources-deployed)
- [Prerequisites](#prerequisites)
  - [Required Tools](#required-tools)
  - [AWS Account Requirements](#aws-account-requirements)
  - [Git Repository Setup](#git-repository-setup)
- [Quick Start](#quick-start)
- [Troubleshooting](#troubleshooting)
  - [Stack Creation Failures](#stack-creation-failures)
  - [OIDC Provider Issues](#oidc-provider-issues)
  - [State Bucket Access](#state-bucket-access)
- [Technologies and Services](#technologies-and-services)
  - [Infrastructure as Code](#infrastructure-as-code)
  - [AWS Services](#aws-services)
  - [Development Tools](#development-tools)
- [Copyright](#copyright)

## Why

Every Terraform or OpenTofu project needs three foundational components: remote state storage, state locking, and CI/CD authentication. Creating these manually for each project leads to inconsistency, security risks, and operational overhead. This project solves the bootstrapping problem by deploying shared backend infrastructure once, enabling all downstream projects to use consistent state management and secure OIDC-based authentication without long-lived credentials.

This foundation serves as the base layer for related projects including [terraform-aws-deployment-roles](https://github.com/stephenabbot/terraform-aws-deployment-roles), which creates project-specific IAM roles that consume the OIDC provider and backend configuration published by this foundation. The foundation is designed for GitHub Actions integration with OIDC authentication, with workflow implementation planned for future releases.

## How

### Architecture

The foundation uses CloudFormation to deploy infrastructure that Terraform projects depend on, avoiding the circular dependency of using Terraform to create Terraform backend resources. All configuration is published to SSM Parameter Store at predictable paths, enabling consuming projects to discover backend settings and OIDC providers without hardcoding values.

The deployment follows a layered approach where the foundation provides shared services, deployment roles provide authentication, and application projects consume both. Git repository information is automatically detected and used for resource naming and tagging, ensuring consistent identification across all infrastructure.

State buckets include versioning, encryption, intelligent tiering, and access logging. DynamoDB tables provide state locking with point-in-time recovery and deletion protection. The OIDC provider is automatically configured based on the git remote origin, supporting GitHub, GitLab, and Bitbucket.

### Script-Based Deployment

The deployment script handles all complexity including prerequisite validation, metadata collection, parameter preparation, and stack deployment. This eliminates manual CloudFormation CLI operations and reduces deployment errors. The script validates git repository state, AWS credentials, required tools, and account permissions before attempting deployment.

Idempotent operations allow running the deployment script multiple times safely. The script detects existing stacks and performs updates rather than failing. Resource listing scripts provide complete inventory of deployed infrastructure with status checks. Destruction scripts include confirmation prompts and handle resource dependencies correctly.

## Resources Deployed

The foundation creates the following AWS resources:

- S3 bucket for Terraform state storage with versioning and encryption
- S3 bucket for access logs with lifecycle policies
- DynamoDB table for state locking with point-in-time recovery
- OIDC provider for GitHub Actions authentication
- IAM role for terraform-aws-deployment-roles project
- SSM parameters publishing backend configuration and role ARNs
- CloudFormation stack managing all resources with consistent tagging

All resources include comprehensive tags for cost allocation, ownership tracking, and resource management. Bucket names and table names incorporate the AWS account ID and region to ensure global uniqueness.

## Prerequisites

### Required Tools

The following tools must be installed and available in your PATH:

- AWS CLI version 2.x for AWS service interaction and authentication
- Bash version 4.x or higher for script execution
- jq for JSON processing in deployment scripts
- Git for repository information detection and version control

### AWS Account Requirements

You need an AWS account with the following:

- IAM permissions to create CloudFormation stacks, S3 buckets, DynamoDB tables, OIDC providers, IAM roles, and SSM parameters
- No existing resources with conflicting names in the target region
- Account must not have reached service quotas for S3 buckets or DynamoDB tables

The deployment uses your current AWS credentials from the AWS CLI configuration. No specific IAM role is required for initial foundation deployment.

### Git Repository Setup

The repository must be:

- Initialized as a git repository with a remote origin configured
- Remote origin must be GitHub, GitLab, or Bitbucket for OIDC provider configuration
- Working directory must be clean with no uncommitted changes or untracked files
- All commits must be pushed to the remote repository

These requirements ensure deployment metadata is accurate and prevent deploying from inconsistent repository states.

## Quick Start

Clone the repository and navigate to the project directory:

```bash
git clone https://github.com/stephenabbot/terraform-aws-cfn-foundation.git
cd terraform-aws-cfn-foundation
```

Review and modify the environment configuration file:

```bash
# Edit .env file with your settings
AWS_REGION=us-east-1
TAG_ENVIRONMENT=prod
TAG_OWNER=your-name
TARGET_DEPLOYMENT_ROLES_REPOSITORY=your-org/terraform-aws-deployment-roles
```

Verify prerequisites and deploy the foundation:

```bash
./scripts/verify-prerequisites.sh
./scripts/deploy.sh
```

The deployment script will automatically detect your git repository information, AWS account details, and OIDC provider configuration. After successful deployment, backend configuration will be available in SSM Parameter Store for consuming projects.

List deployed resources to verify the foundation:

```bash
./scripts/list-deployed-resources.sh
```

## Troubleshooting

### Stack Creation Failures

If the CloudFormation stack fails to create, check the AWS CloudFormation console for detailed error messages. Common issues include:

- Insufficient IAM permissions for the deploying user or role
- Service quota limits reached for S3 buckets or DynamoDB tables
- Existing resources with conflicting names in the account and region
- Invalid parameter values in the .env configuration file

Review the CloudFormation events tab to identify which resource failed and why. The deployment script includes rollback handling, so failed deployments will clean up partial resources automatically.

### OIDC Provider Issues

OIDC provider creation requires valid thumbprints for the identity provider. The deployment script automatically configures thumbprints for GitHub, GitLab, and Bitbucket based on your git remote origin. If OIDC provider creation fails:

- Verify your git remote origin URL is correctly formatted
- Ensure the remote is one of the supported providers
- Check that the OIDC provider does not already exist in your account
- Confirm your AWS account has permissions to create OIDC providers

Only one OIDC provider per identity provider URL can exist in an AWS account. If you need to update an existing provider, delete it first or modify the stack.

### State Bucket Access

If consuming projects cannot access the state bucket, verify:

- SSM parameters exist at /terraform/foundation/s3-state-bucket and /terraform/foundation/dynamodb-lock-table
- The IAM role or user has permissions to read SSM parameters in us-east-1
- The state bucket policy allows access from the consuming project's IAM role
- The DynamoDB table exists and has the correct permissions

Use the list-deployed-resources script to confirm all foundation resources are deployed and accessible. Check IAM policies on consuming project roles to ensure they include S3 and DynamoDB permissions for the backend resources.

## Technologies and Services

### Infrastructure as Code

- CloudFormation for bootstrapping infrastructure that Terraform depends on, avoiding circular dependencies
- Bash scripting for deployment automation, prerequisite validation, and operational workflows

### AWS Services

- S3 for durable state storage with versioning, encryption, and intelligent tiering
- DynamoDB for distributed state locking with point-in-time recovery
- IAM for OIDC provider configuration and deployment role creation
- SSM Parameter Store for publishing backend configuration to consuming projects
- CloudFormation for declarative infrastructure management with drift detection

### Development Tools

- AWS CLI for service interaction and credential management
- Git for version control and repository metadata detection
- jq for JSON processing in deployment scripts and parameter handling
- Bash for cross-platform script execution and automation

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

© 2025 Stephen Abbot - MIT License
