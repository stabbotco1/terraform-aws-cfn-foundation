# Terraform AWS CloudFormation Foundation

## CloudFormation foundation for Terraform backend infrastructure and OIDC authentication

Creates shared S3 state storage, DynamoDB locking, and GitHub Actions OIDC provider using CloudFormation to bootstrap Terraform projects without circular dependencies. Publishes backend configuration to SSM Parameter Store for automatic discovery by consuming projects.

Repository: [foundation-terraform-bootstrap](https://github.com/stephenabbot/foundation-terraform-bootstrap)

## What Problem This Project Solves

Every Terraform or OpenTofu project needs three foundational components: remote state storage, state locking, and CI/CD authentication. Creating these manually for each project leads to inconsistency, security risks, and operational overhead.

- Manual creation of backend infrastructure for each project leads to inconsistency and security risks
- Terraform projects face circular dependency when using Terraform to create Terraform backend resources
- Each project requires secure CI/CD authentication without long-lived credentials
- Consuming projects need to discover backend settings and OIDC providers without hardcoding values
- Operational overhead increases when managing foundational infrastructure across multiple projects

## What This Project Does

Uses CloudFormation to deploy infrastructure that Terraform projects depend on, avoiding circular dependencies. The main CloudFormation template (`bootstrap.yaml`) publishes all configuration to SSM Parameter Store at predictable paths for automatic discovery by consuming projects.

- Creates shared S3 state storage with versioning and encryption for multiple Terraform projects
- Deploys DynamoDB table for state locking with point-in-time recovery capabilities
- Establishes GitHub Actions OIDC provider for secure CI/CD authentication without credentials
- Publishes backend configuration to SSM Parameter Store for consuming project discovery
- Handles all deployment complexity including prerequisite validation and metadata collection
- Provides automated deployment scripts with comprehensive error handling and rollback support

## What This Project Changes

Creates shared backend infrastructure using CloudFormation and publishes configuration to SSM Parameter Store for consuming project discovery.

### Resources Created/Managed

- S3 bucket for Terraform state storage with versioning and encryption
- S3 bucket for access logs with lifecycle policies
- DynamoDB table for state locking with point-in-time recovery
- OIDC provider for GitHub Actions authentication
- IAM role for terraform-aws-deployment-roles project
- SSM parameters publishing backend configuration and role ARNs
- CloudFormation stack managing all resources with consistent tagging

### Functional Changes

- Enables secure CI/CD authentication without long-lived credentials
- Provides centralized state management for multiple Terraform projects
- Establishes consistent resource naming and tagging patterns
- Creates foundation for project-specific IAM role deployment

## Configuration Management

This project uses the `.env.example` pattern for secure configuration management:

- **`.env.example`** - Template with placeholder values (committed to git)
- **`.env`** - Your actual AWS account ID (gitignored, never committed)
- **`config.env`** - Project settings and defaults (committed to git)

**Why this approach:**
- Prevents accidental exposure of AWS account IDs in git history
- Eliminates dependency on GitHub organization-level variables (cost-effective)
- Follows standard development practices for sensitive configuration
- Provides clear setup workflow with validation

**Setup:**
```bash
cp .env.example .env
# Edit .env with your actual AWS account ID
```

The verification script ensures your `.env` configuration matches your current AWS session before deployment.

## IAM Permissions Strategy

The deployment role created by this foundation uses `IAMFullAccess` by design to serve as an "IAM factory" for downstream projects. This broad permission model prevents operational bottlenecks while enabling security optimization at the appropriate layer through observability and automated policy refinement. See [IAM Permissions Strategy](docs/iam-permissions-strategy.md) for detailed reasoning.

## Quick Start

See [prerequisites](https://github.com/stephenabbot/foundation-terraform-bootstrap/blob/main/docs/prerequisites.md) for detailed requirements, [bootstrap sequence flow](https://github.com/stephenabbot/foundation-terraform-bootstrap/blob/main/docs/bootstrap-sequence-flow.md) for the complete automation process, and [scripts directory](https://github.com/stephenabbot/foundation-terraform-bootstrap/tree/main/scripts) for available operations.

```bash
git clone https://github.com/stephenabbot/foundation-terraform-bootstrap.git
cd foundation-terraform-bootstrap

# Configure environment
cp .env.example .env
# Edit .env with your AWS account ID

# Deploy foundation (run from project root)
./scripts/verify-prerequisites.sh
./scripts/deploy.sh

# Verify deployment
./scripts/list-deployed-resources.sh
```

## AWS Well-Architected Framework

This project demonstrates alignment with all six pillars of the [AWS Well-Architected Framework](https://aws.amazon.com/blogs/apn/the-6-pillars-of-the-aws-well-architected-framework/):

### Operational Excellence

- Automated deployment scripts with comprehensive error handling
- Idempotent operations with rollback handling
- Resource listing and status verification capabilities
- Git state validation and parameter store configuration distribution
- Comprehensive tagging and stack termination protection
- Clear documentation and operational workflows

### Security

- OIDC provider for secure CI/CD authentication without long-lived credentials
- S3 bucket encryption with bucket key enabled and public access blocked
- IAM roles with least privilege and DynamoDB point-in-time recovery
- Resource-level tagging for governance and git repository validation
- Parameter store for secure configuration distribution
- CloudFormation stack termination protection and access logging

### Reliability

- S3 versioning for state recovery and DynamoDB with point-in-time recovery
- Multi-region OIDC provider support and comprehensive error handling
- Orphaned resource detection and cleanup with stack rollback handling
- Resource retention policies and idempotent operations
- Import capability for orphaned resources and automated prerequisite validation

### Performance Efficiency

- S3 Intelligent Tiering for automatic optimization based on access patterns
- DynamoDB on-demand billing with automatic scaling
- CloudFormation for infrastructure as code and automated deployment scripts
- Parameter store for efficient configuration distribution
- Regional resource naming and bucket key enabled for S3 encryption efficiency

### Cost Optimization

- S3 Intelligent Tiering automatically moves objects to cheaper storage classes
- DynamoDB on-demand billing eliminates provisioned capacity waste
- S3 lifecycle policies for log retention and comprehensive tagging for cost allocation
- Shared infrastructure reduces per-project overhead
- OIDC eliminates costs of managing long-lived credentials
- CloudFormation prevents resource drift and automated cleanup prevents waste

### Sustainability

- Serverless managed services reduce infrastructure overhead
- S3 Intelligent Tiering reduces storage energy consumption
- DynamoDB on-demand reduces idle resource consumption
- Automated operations reduce manual intervention and shared foundation reduces duplicate infrastructure
- CloudFormation prevents resource sprawl and lifecycle policies prevent indefinite data retention

## Technologies Used

| Technology | Purpose | Implementation |
|------------|---------|----------------|
| Kiro CLI with Claude | AI-assisted development, design, and implementation |
| AWS CloudFormation | Infrastructure as code and stack management | Stack deployment with comprehensive resource tagging and dependency management |
| AWS Systems Manager Parameter Store | Configuration distribution and service discovery | Predictable parameter paths for backend configuration publishing |
| AWS Identity and Access Management OIDC Provider | Secure CI/CD authentication | GitHub Actions trust relationships without long-lived credentials |
| AWS DynamoDB | Terraform state locking with point-in-time recovery | Pay-per-request billing with point-in-time recovery for state coordination |
| AWS S3 Intelligent Tiering | Automatic storage cost optimization | State storage with automatic tier transitions based on access patterns |
| AWS S3 Server-Side Encryption | Data protection with Amazon S3-managed keys | AES256 server-side encryption for state storage security |
| AWS S3 Versioning | State recovery and backup capabilities | Version-enabled buckets for state history and recovery |
| AWS S3 Lifecycle Policies | Log retention and cost management | Automated log cleanup and storage class transitions |
| AWS IAM Roles | Least privilege access control | Role-based access for terraform-aws-deployment-roles project |
| Bash Scripting | Deployment automation and validation | Prerequisite validation, deployment orchestration, and resource listing |
| Git Repository Metadata | Resource naming and tagging automation | Automated resource naming from repository data and commit information |
| JSON Query (jq) | Data processing in deployment scripts | Parameter parsing, output processing, and configuration manipulation |
| AWS CLI | Service interaction and authentication | CloudFormation operations, parameter management, and service interaction |
| OpenSSL | OIDC provider thumbprint calculation | GitHub OIDC provider thumbprint generation for trust relationships |

## Copyright

© 2025 Stephen Abbot - MIT License
