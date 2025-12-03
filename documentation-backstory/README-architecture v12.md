# AWS Terraform Foundation Suite - Architecture Documentation v11

## Executive Summary

This document defines a four-tier infrastructure-as-code architecture for AWS deployments using OpenTofu (Terraform-compatible). The architecture separates concerns into foundation resources, shared modules, authorization management, and application deployments while eliminating sensitive data from source control and adhering to principle of least privilege.

### Architecture Goals

- No sensitive data in source code or Git repositories
- Minimal, sensible project structure
- Idempotent deployments without conditional bootstrapping logic
- Centralized authorization management
- Reusable shared infrastructure
- MIT-licensed public GitHub repositories
- Native development environment with consistent tooling
- Automated validation and deployment workflows

### Document Version

- **Version**: 12.0
- **Date**: 2024-12-03
- **Status**: Implementation Ready

---

## High-Level Architecture

### Four-Tier Structure

**Project 1: CloudFormation Foundation**

- Purpose: Create shared OpenTofu backend resources
- Technology: AWS CloudFormation
- Deployment: One-time manual deployment via script
- Output: S3 bucket, DynamoDB table, GitHub OIDC provider, Parameter Store values

**Project 2: Shared Modules**

- Purpose: Reusable Terraform modules and scripts
- Technology: OpenTofu modules
- Scope: Deployment context, tagging, common patterns
- Distribution: Git tags with version pinning

**Project 3: Deployment Roles**

- Purpose: Manage deployment authorization for application projects
- Technology: OpenTofu
- Scope: Creates project-specific IAM roles with appropriate policies
- Security: Centralized control prevents privilege escalation

**Project 4+: Application Deployments**

- Purpose: Deploy actual infrastructure resources
- Technology: OpenTofu
- Pattern: VPC foundations, EKS platforms, application resources
- Authorization: Assumes roles created by Project 3

### Project Relationships

```
Project 1: CloudFormation Foundation
    ↓ creates
[Shared Resources: S3, DynamoDB, OIDC, Parameter Store]
    ↓ consumed by
Project 2: Shared Modules ← reads from Parameter Store
    ↓ provides modules to
Project 3: Deployment Roles ← uses shared modules
    ↓ creates
[IAM Deployment Roles]
    ↓ assumed by
Project 4+: Applications ← uses shared backend, modules, and roles
```

### Umbrella Project

**Name**: `aws-terraform-foundation-suite`
**Purpose**: Documentation and project coordination
**Contents**: Architecture docs, deployment guides, project relationships, quick start guides

---

## Project Naming Standards

### Repository Names

```
Project 1: terraform-aws-cfn-foundation
Project 2: terraform-aws-shared-modules
Project 3: terraform-aws-deployment-roles
Project 4+: terraform-aws-{project-name}
Umbrella:   aws-terraform-foundation-suite
```

**Rationale**:

- "cfn-foundation" clearly indicates CloudFormation-based bootstrap
- "shared-modules" follows Terraform community convention
- Consistent prefix enables easy discovery

### Resource Naming Convention

**Pattern**: `{deployment-id}-{resource-type}-{discriminator}`

**Examples**:

```
vpc-foundation-dev-vpc
vpc-foundation-dev-subnet-public-1a
eks-platform-prod-use1-cluster
hosted-zone-example-com-zone
```

**Rules**:

- Use kebab-case (lowercase with hyphens) for all AWS resources
- Do NOT use CamelCase (inconsistent AWS support)
- Do NOT include account ID in resource names (use tags instead)
- Maximum length varies by service (see Resource Naming Constraints section)

### Terraform Logical Names

**Pattern**: `{resource_type}_{purpose}` (snake_case)

**Examples**:

```hcl
resource "aws_vpc" "main" { }
resource "aws_subnet" "public_1a" { }
resource "aws_security_group" "web_server" { }
```

### Variable Names

**Pattern**: `{purpose}_{qualifier}` (snake_case)

**Examples**:

```hcl
variable "environment" { }
variable "vpc_cidr" { }
variable "enable_nat_gateway" { }
```

---

## Parameter Store Hierarchy

### Standard Hierarchy

```
/terraform/
├── foundation/
│   ├── s3-state-bucket
│   ├── dynamodb-lock-table
│   ├── oidc-github-provider
│   └── shared-modules-repository
└── deployment-roles/
    ├── cfn-foundation-role-arn
    ├── vpc-foundation-dev-role-arn
    ├── vpc-foundation-prod-role-arn
    ├── eks-platform-prod-use1-role-arn
    └── hosted-zone-example-com-role-arn
```

### Naming Convention

**Pattern**: `/terraform/{category}/{resource-name}`

**Categories**:

- `foundation` - Shared OpenTofu backend resources
- `deployment-roles` - Deployment role ARNs (using deployment-id)

**Benefits**:

- Hierarchical organization
- Easy bulk retrieval (`get-parameters-by-path`)
- Clear ownership and purpose
- No account ID or sensitive data in parameter names

---

## Deployment Context and Identification

### Deployment ID Generation

The deployment context module generates deterministic identifiers for all resources.

**Components** (all optional except project_name):

- `project_name` - Required (e.g., "vpc-foundation")
- `environment` - Optional (e.g., "dev", "staging", "prod")
- `region_code` - Optional (e.g., "use1", "usw2")
- `instance_name` - Optional (e.g., "example-com" for domain-specific)

**Generated IDs**:

```
deployment_id:    vpc-foundation-dev
short_id:         vpc-dev
ultra_short_id:   vpcde
```

**Usage Examples**:

```hcl
# Singleton deployment (no environment/region variants)
module "context" {
  source       = "git::https://github.com/USERNAME/terraform-aws-shared-modules.git//modules/deployment-context?ref=v1.0.0"
  project_name = "cfn-foundation"
}
# deployment_id = "cfn-foundation"

# Environment-specific deployment
module "context" {
  source       = "git::https://github.com/USERNAME/terraform-aws-shared-modules.git//modules/deployment-context?ref=v1.0.0"
  project_name = "vpc-foundation"
  environment  = "dev"
}
# deployment_id = "vpc-foundation-dev"

# Multi-region deployment
module "context" {
  source       = "git::https://github.com/USERNAME/terraform-aws-shared-modules.git//modules/deployment-context?ref=v1.0.0"
  project_name = "eks-platform"
  environment  = "prod"
  region_code  = "use1"
}
# deployment_id = "eks-platform-prod-use1"

# Domain-specific deployment
module "context" {
  source        = "git::https://github.com/USERNAME/terraform-aws-shared-modules.git//modules/deployment-context?ref=v1.0.0"
  project_name  = "hosted-zone"
  instance_name = "example-com"
}
# deployment_id = "hosted-zone-example-com"
```

### State Key Naming

**Pattern**: `{project-name}/{deployment-id}/terraform.tfstate`

**Examples**:

```
cfn-foundation/cfn-foundation/terraform.tfstate
vpc-foundation/vpc-foundation-dev/terraform.tfstate
eks-platform/eks-platform-prod-use1/terraform.tfstate
hosted-zone/hosted-zone-example-com/terraform.tfstate
```

### Role Naming

**Pattern**: `terraform-{deployment-id}-deploy`

**Examples**:

```
terraform-cfn-foundation-deploy
terraform-vpc-foundation-dev-deploy
terraform-eks-platform-prod-use1-deploy
```

---

## Resource Naming Constraints

### AWS Service-Specific Constraints

**S3 Buckets**:

- Length: 3-63 characters
- Characters: lowercase letters, numbers, hyphens, periods
- Pattern: `[a-z0-9.-]+`
- Case: lowercase only

**RDS Identifiers**:

- Length: 1-63 characters
- Characters: lowercase letters, numbers, hyphens
- Pattern: `[a-z0-9-]+`
- Case: lowercase only (automatically converted)

**Lambda Functions**:

- Length: 1-64 characters
- Characters: letters, numbers, hyphens, underscores
- Pattern: `[a-zA-Z0-9-_]+`
- Case: case-sensitive

**IAM Roles**:

- Length: 1-64 characters
- Characters: letters, numbers, plus, equals, comma, period, at, hyphens
- Pattern: `[a-zA-Z0-9+=,.@-]+`
- Case: case-sensitive

**DynamoDB Tables**:

- Length: 3-255 characters
- Characters: letters, numbers, hyphens, underscores, periods
- Pattern: `[a-zA-Z0-9._-]+`
- Case: case-sensitive

**EC2 Security Groups**:

- Length: 1-255 characters
- Characters: letters, numbers, spaces, hyphens, underscores, periods, colons, slashes
- Case: case-insensitive

### Most Restrictive Common Denominator

**Recommendation**: Use kebab-case (lowercase with hyphens) for all resources.

**Pattern**: `[a-z0-9-]+`

**Rationale**: Works across all AWS services, prevents case-sensitivity issues.

### Short ID Usage Guidelines

**When to use deployment_id** (full name):

- VPC, subnets, route tables
- Security groups
- IAM roles
- Lambda functions
- Resources with generous length limits

**When to use short_id** (abbreviated):

- S3 buckets (63-char limit)
- RDS instances (63-char limit)
- Resources approaching length limits

**When to use ultra_short_id** (minimal):

- Resources with extreme length constraints (rare)
- Only when deployment_id and short_id exceed limits

**Warning**: Shorter IDs increase collision risk. Always include environment in deployment context.

---

## Git Versioning Strategy

### Version Pinning with Git Tags

**Standard approach**:

```hcl
module "tags" {
  source = "git::https://github.com/USERNAME/terraform-aws-shared-modules.git//modules/tags?ref=v1.2.3"
}
```

**Benefits**:

- Industry standard Terraform pattern
- Clean repository structure
- Git handles versioning
- Easy version history

### History Management

**Problem**: Git history may contain sensitive data or unnecessary commits.

**Solution**: Pre-push squash to clean history.

**Process**:

```bash
# Squash all history before pushing
git checkout --orphan new-main
git add -A
git commit -m "Release v1.2.3"
git branch -D main
git branch -m main
git push -f origin main
git tag v1.2.3
git push origin v1.2.3
```

**Result**: Single commit per version + version tag, no historical baggage.

**Documentation**: Include squash process in shared-modules README.

### Semantic Versioning

**Format**: `vMAJOR.MINOR.PATCH`

**Rules**:

- MAJOR: Breaking changes
- MINOR: New features (backward compatible)
- PATCH: Bug fixes

**Starting version**: v1.0.0

**Rationale**: Indicates production-ready, stable modules.

---

## Project 1: CloudFormation Foundation

### Repository Name

`terraform-aws-cfn-foundation`

### Purpose

Solves the chicken-and-egg problem of OpenTofu state management by using CloudFormation (which manages its own state) to create shared backend resources.

### Resources Created

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

### CloudFormation Stack Configuration

**Stack Name**: `terraform-shared-infrastructure`
**Termination Protection**: Enabled
**Stack Policy**: Prevent updates to critical resources

### Deployment Method

Automated via script with validation and state handling:

**Deploy Script Features:**
- Handles `ROLLBACK_COMPLETE` state (auto-cleanup and recreate)
- Handles `UPDATE_ROLLBACK_COMPLETE` state (allows updates)
- Validates existing OIDC provider
- Idempotent (safe to run multiple times)
- Interactive confirmation for updates

**Destroy Script Features:**
- Checks for Project 3 (deployment-roles) resources via tags
- Checks for state files in S3 bucket
- Cleans up orphaned resources from failed deployments
- Supports `--auto-approve` flag for automation
- Requires manual confirmation by default

**Usage:**
```bash
# Deploy (interactive)
./scripts/deploy.sh

# Destroy (interactive)
./scripts/destroy.sh

# Destroy (automated)
./scripts/destroy.sh --auto-approve
```

**State Handling:**
The deploy script automatically handles all CloudFormation states:
- `ROLLBACK_COMPLETE` - Deletes failed stack and recreates
- `UPDATE_ROLLBACK_COMPLETE` - Allows updates
- `CREATE_COMPLETE` / `UPDATE_COMPLETE` - Normal updates
- `*_IN_PROGRESS` - Blocks with helpful message

```bash
#!/bin/bash
# scripts/deploy.sh

set -euo pipefail

echo "Deploying CloudFormation foundation..."

# Check for existing OIDC provider
EXISTING_OIDC=$(aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn" \
  --output text)

if [ -n "$EXISTING_OIDC" ]; then
  echo "ℹ Existing OIDC provider found: $EXISTING_OIDC"
  echo "  Will reuse existing provider"
  OIDC_ACTION="reuse"
else
  echo "ℹ No existing OIDC provider - will create new one"
  OIDC_ACTION="create"
fi

# Deploy CloudFormation stack
aws cloudformation create-stack \
  --stack-name terraform-shared-infrastructure \
  --template-body file://bootstrap.yaml \
  --capabilities CAPABILITY_IAM \
  --parameters ParameterKey=OidcAction,ParameterValue=$OIDC_ACTION \
  --enable-termination-protection

echo "✓ CloudFormation stack deployment initiated"
echo "  Waiting for stack creation to complete..."

aws cloudformation wait stack-create-complete \
  --stack-name terraform-shared-infrastructure

echo "✓ Foundation deployment complete"
```

### S3 Lifecycle Configuration

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.terraform_state.id

  # Active state files
  rule {
    id     = "active-state"
    status = "Enabled"
    
    transition {
      days          = 0
      storage_class = "INTELLIGENT_TIERING"
    }
  }

  # Backups
  rule {
    id     = "backups"
    status = "Enabled"
    
    filter {
      prefix = "backups/"
    }
    
    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }
    
    expiration {
      days = 365
    }
  }
}
```

**Note**: S3 provides 11 9's durability. Single-region storage with versioning is sufficient for most use cases. Cross-region replication can be added for mission-critical deployments requiring additional availability guarantees.

### OIDC Provider Validation

```bash
# Validate existing OIDC provider
PROVIDER_ARN=$(aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn" \
  --output text)

if [ -n "$PROVIDER_ARN" ]; then
  # Validate thumbprint
  THUMBPRINT=$(aws iam get-open-id-connect-provider \
    --open-id-connect-provider-arn "$PROVIDER_ARN" \
    --query 'ThumbprintList[0]' \
    --output text)
  
  EXPECTED_THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"
  
  if [ "$THUMBPRINT" = "$EXPECTED_THUMBPRINT" ]; then
    echo "✓ Thumbprint is valid"
  else
    echo "⚠ Thumbprint mismatch - may need update"
  fi
  
  # Validate audience
  AUDIENCES=$(aws iam get-open-id-connect-provider \
    --open-id-connect-provider-arn "$PROVIDER_ARN" \
    --query 'ClientIDList' \
    --output json)
  
  if echo "$AUDIENCES" | grep -q "sts.amazonaws.com"; then
    echo "✓ Audience includes sts.amazonaws.com"
  else
    echo "⚠ Missing required audience: sts.amazonaws.com"
  fi
fi
```

### Outputs

CloudFormation stack outputs automatically populate Parameter Store.

### Deletion Sequence

Project 1 must be destroyed last, after all Projects 2, 3, and 4+ are destroyed.

**Destruction Dependency Chain:**

Each project checks only its immediate dependents, creating a chain of responsibility:

```
Project 4+ (Applications)
    ↓ blocks
Project 3 (deployment-roles) ← checks for downstream applications
    ↓ blocks
Project 1 (cfn-foundation) ← checks ONLY for Project 3
```

**Project 1 Destruction Checks:**
1. **State files** in S3 bucket (any project using the shared backend)
2. **Resources tagged** with `Project=terraform-aws-deployment-roles`

If either check fails, destruction is blocked until Project 3 is destroyed first.

**Project 3 Destruction Checks:**
- Resources tagged with downstream project names (Project 4+)
- Ensures no applications depend on the deployment roles

This chain ensures proper destruction order without complex cross-project logic.

---

## Project 2: Shared Modules

### Repository Name

`terraform-aws-shared-modules`

### Purpose

Centralized repository of reusable Terraform modules, scripts, and common patterns used across all projects.

### Module Structure

```
terraform-aws-shared-modules/
├── modules/
│   ├── deployment-context/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── tags/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   └── common-data-sources/
│       ├── main.tf
│       ├── outputs.tf
│       └── README.md
├── scripts/
│   ├── setup-project-secrets.sh
│   ├── validate-resource-names.sh
│   └── analyze-iam-policy.sh
├── docs/
│   ├── deployment-context.md
│   ├── tagging-strategy.md
│   └── naming-conventions.md
└── README.md
```

### Deployment Context Module

**Location**: `modules/deployment-context/`

**Purpose**: Generate deterministic deployment identifiers.

**Implementation**:

```hcl
# modules/deployment-context/variables.tf
variable "project_name" {
  type        = string
  description = "Project name (required)"
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (optional: dev, staging, prod)"
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (optional: use1, usw2, euw1)"
}

variable "instance_name" {
  type        = string
  default     = null
  description = "Instance name (optional: for domain-specific deployments)"
}

# modules/deployment-context/main.tf
locals {
  # Full deployment ID
  deployment_id = join("-", compact([
    var.project_name,
    var.environment,
    var.region_code,
    var.instance_name
  ]))
  
  # Short ID (first 3 chars of each component)
  short_components = [
    for component in compact([
      var.project_name,
      var.environment,
      var.region_code,
      var.instance_name
    ]) : substr(component, 0, min(3, length(component)))
  ]
  short_id = join("-", local.short_components)
  
  # Ultra-short ID (first 2 chars, no hyphens)
  ultra_short_id = join("", [
    for component in compact([
      var.project_name,
      var.environment,
      var.region_code,
      var.instance_name
    ]) : substr(component, 0, min(2, length(component)))
  ])
  
  # Parameter store prefix
  parameter_prefix = "/terraform/${var.project_name}/${local.deployment_id}"
  
  # State key
  state_key = "${var.project_name}/${local.deployment_id}/terraform.tfstate"
  
  # Role name
  role_name = "terraform-${local.deployment_id}-deploy"
}

# modules/deployment-context/outputs.tf
output "deployment_id" {
  value       = local.deployment_id
  description = "Full deployment identifier"
}

output "short_id" {
  value       = local.short_id
  description = "Abbreviated deployment identifier"
}

output "ultra_short_id" {
  value       = local.ultra_short_id
  description = "Ultra-short identifier for restrictive limits"
}

output "resource_name_prefix" {
  value       = local.deployment_id
  description = "Prefix for resource names (alias for deployment_id)"
}

output "parameter_prefix" {
  value       = local.parameter_prefix
  description = "Parameter Store path prefix"
}

output "state_key" {
  value       = local.state_key
  description = "S3 state file key"
}

output "role_name" {
  value       = local.role_name
  description = "IAM role name for deployment"
}
```

### Tagging Module

**Location**: `modules/tags/`

**Purpose**: Generate consistent tags across all resources with validation.

**Implementation**:

```hcl
# modules/tags/variables.tf
variable "project_name" {
  type        = string
  description = "Project name (required)"
}

variable "environment" {
  type        = string
  description = "Environment (required)"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod"
  }
}

variable "owner" {
  type        = string
  description = "Team or individual responsible"
  default     = "CHANGE_ME"
  
  validation {
    condition     = var.owner != "CHANGE_ME"
    error_message = "Owner must be customized (cannot be 'CHANGE_ME')"
  }
}

variable "deployment_id" {
  type        = string
  description = "Deployment identifier from deployment-context module"
}

# modules/tags/main.tf
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# modules/tags/outputs.tf
output "tags" {
  value = {
    Project      = var.project_name
    Environment  = var.environment
    DeploymentId = var.deployment_id
    Owner        = var.owner
    AccountId    = data.aws_caller_identity.current.account_id
    Region       = data.aws_region.current.name
    DeployedBy   = data.aws_caller_identity.current.arn
    ManagedBy    = "opentofu"
  }
  description = "Standard tags for all resources"
}
```

### Common Data Sources Module

**Location**: `modules/common-data-sources/`

**Purpose**: Centralize frequently used data sources.

```hcl
# modules/common-data-sources/main.tf
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

# modules/common-data-sources/outputs.tf
output "account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "AWS Account ID"
}

output "caller_arn" {
  value       = data.aws_caller_identity.current.arn
  description = "ARN of the calling identity"
}

output "region" {
  value       = data.aws_region.current.name
  description = "AWS Region"
}

output "partition" {
  value       = data.aws_partition.current.partition
  description = "AWS Partition"
}
```

### Version Management

**Tagging strategy**: Semantic versioning with git tags
**Starting version**: v1.0.0
**Update process**: Squash history, tag, push

**Example**:

```bash
# Release new version
git checkout --orphan new-main
git add -A
git commit -m "Release v1.1.0 - Add deployment-context module"
git branch -D main
git branch -m main
git push -f origin main
git tag v1.1.0
git push origin v1.1.0
```

---

## Project 3: Deployment Roles

### Repository Name

`terraform-aws-deployment-roles`

### Purpose

Centralized management of IAM roles for application deployments. Prevents privilege escalation by separating authorization management from application deployment.

### Backend Configuration

Uses shared resources created by Project 1:

```hcl
terraform {
  backend "s3" {
    bucket         = "REPLACE_FROM_PARAMETER_STORE"
    key            = "deployment-roles/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "REPLACE_FROM_PARAMETER_STORE"
    encrypt        = true
  }
}
```

**Implementation**: Use partial backend configuration with `-backend-config` flags.

### Data Sources for Shared Resources

```hcl
data "aws_ssm_parameter" "s3_bucket" {
  name = "/terraform/foundation/s3-state-bucket"
}

data "aws_ssm_parameter" "dynamodb_table" {
  name = "/terraform/foundation/dynamodb-lock-table"
}

data "aws_ssm_parameter" "oidc_provider_arn" {
  name = "/terraform/foundation/oidc-github-provider"
}
```

### IAM Role Pattern

Each application project receives a dedicated role:

```hcl
# Determine GitHub owner (user or organization)
data "external" "github_owner" {
  program = ["bash", "-c", "gh api user --jq '{login: .login, type: .type}' 2>/dev/null || echo '{}'"]
}

locals {
  github_owner = data.external.github_owner.result.login
}

resource "aws_iam_role" "vpc_foundation_deploy" {
  name = "terraform-vpc-foundation-dev-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_ssm_parameter.oidc_provider_arn.value
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${local.github_owner}/terraform-aws-vpc-foundation:*"
          }
        }
      }
    ]
  })

  tags = module.tags.tags
}

resource "aws_iam_role_policy_attachment" "vpc_foundation_deploy" {
  role       = aws_iam_role.vpc_foundation_deploy.name
  policy_arn = aws_iam_policy.vpc_foundation_policy.arn
}

resource "aws_iam_policy" "vpc_foundation_policy" {
  name        = "terraform-vpc-foundation-dev-policy"
  description = "Deployment permissions for VPC foundation project"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVpc",
          "ec2:CreateSubnet",
          "ec2:CreateRouteTable",
          "ec2:CreateInternetGateway",
          "ec2:CreateNatGateway",
          "ec2:AllocateAddress",
          "ec2:CreateTags",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeRouteTables",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeNatGateways",
          "ec2:DescribeAddresses"
        ]
        Resource = "*"
      }
    ]
  })
}
```

### Role Naming Convention

**Pattern**: `terraform-{deployment-id}-deploy`

**Examples**:

```
terraform-vpc-foundation-dev-deploy
terraform-eks-platform-prod-use1-deploy
terraform-hosted-zone-example-com-deploy
```

### Policy Principle

**Phase 1: Initial Deployment (Permissive)**

- Create role with broad permissions for resource types
- Deploy resources successfully
- Document actual API calls made

**Phase 2: Permission Refinement (Optional)**

- Enable CloudTrail if not already enabled
- Use IAM Access Analyzer to generate minimal policy
- Update role with refined permissions
- Redeploy to verify

**Note**: CloudTrail is NOT required for basic deployment. Phase 2 is optional for security-conscious environments.

### Output to Parameter Store

```hcl
resource "aws_ssm_parameter" "vpc_foundation_dev_role_arn" {
  name  = "/terraform/deployment-roles/vpc-foundation-dev-role-arn"
  type  = "String"
  value = aws_iam_role.vpc_foundation_deploy.arn

  tags = module.tags.tags
}
```

---

## Project 4+: Application Deployments

### Repository Naming Pattern

```
terraform-aws-vpc-foundation
terraform-aws-eks-platform
terraform-aws-{resource-type}
```

### Purpose

Deploy actual infrastructure resources using shared backend, modules, and project-specific deployment roles.

### Backend Configuration

Identical pattern to Project 3, with unique state key:

```hcl
terraform {
  backend "s3" {
    bucket         = "REPLACE_FROM_PARAMETER_STORE"
    key            = "vpc-foundation/vpc-foundation-dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "REPLACE_FROM_PARAMETER_STORE"
    encrypt        = true
  }
}
```

### Module Usage

```hcl
# Deployment context
module "context" {
  source       = "git::https://github.com/USERNAME/terraform-aws-shared-modules.git//modules/deployment-context?ref=v1.0.0"
  project_name = "vpc-foundation"
  environment  = "dev"
}

# Tags
module "tags" {
  source        = "git::https://github.com/USERNAME/terraform-aws-shared-modules.git//modules/tags?ref=v1.0.0"
  project_name  = "vpc-foundation"
  environment   = "dev"
  deployment_id = module.context.deployment_id
  owner         = var.owner
}

# Resources
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = merge(
    module.tags.tags,
    {
      Name = "${module.context.deployment_id}-vpc"
    }
  )
}
```

### GitHub Actions OIDC Authentication

```yaml
name: Deploy Infrastructure

on:
  workflow_dispatch:  # Manual trigger initially

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOYMENT_ROLE_ARN }}
          aws-region: us-east-1
      
      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@v1
      
      - name: Verify Prerequisites
        run: ./scripts/verify-prerequisites.sh
      
      - name: Validate Resource Names
        run: ./scripts/validate-resource-names.sh
      
      - name: OpenTofu Init
        run: tofu init -backend-config="bucket=${{ secrets.TF_STATE_BUCKET }}"
      
      - name: OpenTofu Plan
        run: tofu plan -out=tfplan
      
      - name: OpenTofu Apply
        run: tofu apply tfplan
```

### GitHub Secrets Required

Per project:

- `AWS_DEPLOYMENT_ROLE_ARN` - From Parameter Store
- `TF_STATE_BUCKET` - From Parameter Store
- `TF_STATE_DYNAMODB_TABLE` - From Parameter Store

**Setup**: Use `setup-project-secrets.sh` script from shared-modules.

---

## Standard Scripts

All projects include these scripts in `scripts/` directory:

### verify-prerequisites.sh

**Purpose**: Validate all prerequisites before deployment.

**Implementation**:

```bash
#!/bin/bash
# scripts/verify-prerequisites.sh

set -euo pipefail

FAILURES=()

check_aws_auth() {
  if aws sts get-caller-identity &>/dev/null; then
    echo "✓ AWS authentication valid"
    return 0
  else
    echo "✗ AWS authentication failed"
    FAILURES+=("AWS authentication")
    return 1
  fi
}

check_github_secrets() {
  if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
    local required_secrets=("AWS_DEPLOYMENT_ROLE_ARN" "TF_STATE_BUCKET" "TF_STATE_DYNAMODB_TABLE")
    local missing=()
    
    for secret in "${required_secrets[@]}"; do
      if [ -z "${!secret:-}" ]; then
        echo "✗ Missing GitHub secret: $secret"
        missing+=("$secret")
      else
        echo "✓ GitHub secret exists: $secret"
      fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
      FAILURES+=("GitHub secrets: ${missing[*]}")
      return 1
    fi
  else
    echo "ℹ Skipping GitHub secrets check (running locally)"
  fi
  return 0
}

check_parameter_store() {
  local params=(
    "/terraform/foundation/s3-state-bucket"
    "/terraform/foundation/dynamodb-lock-table"
  )
  
  for param in "${params[@]}"; do
    if aws ssm get-parameter --name "$param" &>/dev/null; then
      echo "✓ Parameter exists: $param"
    else
      echo "✗ Missing parameter: $param"
      FAILURES+=("Parameter: $param")
    fi
  done
}

check_tag_defaults() {
  if grep -q "CHANGE_ME" terraform.tfvars 2>/dev/null; then
    echo "✗ Default tag values detected in terraform.tfvars"
    FAILURES+=("Tag defaults not customized")
    return 1
  fi
  echo "✓ No default tag values detected"
  return 0
}

# Run all checks
check_aws_auth
check_github_secrets
check_parameter_store
check_tag_defaults

# Report results
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo ""
  echo "✓ All prerequisites satisfied"
  exit 0
else
  echo ""
  echo "✗ Prerequisites check failed:"
  for failure in "${FAILURES[@]}"; do
    echo "  - $failure"
  done
  exit 1
fi
```

### validate-resource-names.sh

**Purpose**: Validate resource names against AWS constraints before deployment.

**Implementation**:

```bash
#!/bin/bash
# scripts/validate-resource-names.sh

set -euo pipefail

echo "Validating resource names against AWS constraints..."

# Generate plan
tofu plan -out=tfplan.binary >/dev/null 2>&1
tofu show -json tfplan.binary > tfplan.json

VIOLATIONS=()

# Validate S3 bucket names
S3_BUCKETS=$(jq -r '.planned_values.root_module.resources[]? | select(.type=="aws_s3_bucket") | .values.bucket' tfplan.json 2>/dev/null || echo "")

if [ -n "$S3_BUCKETS" ]; then
  echo "Checking S3 bucket names..."
  while IFS= read -r bucket; do
    [ -z "$bucket" ] && continue
    
    if [[ "$bucket" =~ [A-Z] ]]; then
      echo "✗ S3 bucket contains uppercase: $bucket"
      VIOLATIONS+=("S3 bucket '$bucket': must be lowercase only")
    elif [ ${#bucket} -lt 3 ] || [ ${#bucket} -gt 63 ]; then
      echo "✗ S3 bucket length invalid: $bucket (${#bucket} chars)"
      VIOLATIONS+=("S3 bucket '$bucket': must be 3-63 characters")
    elif [[ ! "$bucket" =~ ^[a-z0-9.-]+$ ]]; then
      echo "✗ S3 bucket invalid characters: $bucket"
      VIOLATIONS+=("S3 bucket '$bucket': only lowercase, numbers, hyphens, periods allowed")
    else
      echo "✓ S3 bucket valid: $bucket"
    fi
  done <<< "$S3_BUCKETS"
fi

# Validate RDS identifiers
RDS_INSTANCES=$(jq -r '.planned_values.root_module.resources[]? | select(.type=="aws_db_instance") | .values.identifier' tfplan.json 2>/dev/null || echo "")

if [ -n "$RDS_INSTANCES" ]; then
  echo "Checking RDS instance identifiers..."
  while IFS= read -r identifier; do
    [ -z "$identifier" ] && continue
    
    if [[ "$identifier" =~ [A-Z] ]]; then
      echo "✗ RDS identifier contains uppercase: $identifier"
      VIOLATIONS+=("RDS identifier '$identifier': must be lowercase only")
    elif [ ${#identifier} -lt 1 ] || [ ${#identifier} -gt 63 ]; then
      echo "✗ RDS identifier length invalid: $identifier"
      VIOLATIONS+=("RDS identifier '$identifier': must be 1-63 characters")
    elif [[ ! "$identifier" =~ ^[a-z0-9-]+$ ]]; then
      echo "✗ RDS identifier invalid characters: $identifier"
      VIOLATIONS+=("RDS identifier '$identifier': only lowercase, numbers, hyphens allowed")
    else
      echo "✓ RDS identifier valid: $identifier"
    fi
  done <<< "$RDS_INSTANCES"
fi

# Cleanup
rm -f tfplan.binary tfplan.json

# Report results
if [ ${#VIOLATIONS[@]} -eq 0 ]; then
  echo ""
  echo "✓ All resource names validated successfully"
  exit 0
else
  echo ""
  echo "✗ Resource name validation failed:"
  for violation in "${VIOLATIONS[@]}"; do
    echo "  - $violation"
  done
  echo ""
  echo "Fix naming violations and try again."
  exit 1
fi
```

### deploy.sh

**Purpose**: Idempotent deployment with validation gates.

**Implementation**:

```bash
#!/bin/bash
# scripts/deploy.sh

set -euo pipefail

echo "Starting deployment..."

# Detect environment
if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
  echo "Running in GitHub Actions"
  INTERACTIVE=false
else
  echo "Running locally"
  INTERACTIVE=true
fi

# Verify prerequisites
echo ""
echo "Step 1: Verifying prerequisites..."
./scripts/verify-prerequisites.sh || exit 1

# Validate resource names
echo ""
echo "Step 2: Validating resource names..."
./scripts/validate-resource-names.sh || exit 1

# Initialize Terraform
echo ""
echo "Step 3: Initializing OpenTofu..."
tofu init

# Plan
echo ""
echo "Step 4: Planning deployment..."
tofu plan -out=tfplan

# Apply
echo ""
echo "Step 5: Applying deployment..."
if [ "$INTERACTIVE" = "true" ]; then
  read -p "Proceed with deployment? (yes/no): " confirm
  if [ "$confirm" != "yes" ]; then
    echo "Deployment cancelled"
    exit 0
  fi
fi

tofu apply tfplan

echo ""
echo "✓ Deployment complete"
```

### destroy.sh

**Purpose**: Safe destruction with backups and confirmation.

**Implementation**:

```bash
#!/bin/bash
# scripts/destroy.sh

set -euo pipefail

echo "Starting destruction process..."

# Detect environment
if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
  echo "✗ Destruction not allowed in GitHub Actions"
  echo "  Run locally for safety"
  exit 1
fi

# Get deployment context
DEPLOYMENT_ID=$(tofu output -raw deployment_id 2>/dev/null || echo "unknown")
STATE_BUCKET=$(aws ssm get-parameter --name "/terraform/foundation/s3-state-bucket" --query 'Parameter.Value' --output text)
STATE_KEY=$(tofu output -raw state_key 2>/dev/null || echo "unknown/terraform.tfstate")

# Check for dependent resources
echo "Checking for dependent resources..."
DEPENDENT_RESOURCES=$(aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=DeploymentId,Values=${DEPLOYMENT_ID}" \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output text 2>/dev/null || echo "")

if [ -n "$DEPENDENT_RESOURCES" ]; then
  echo "✗ Found dependent resources:"
  echo "$DEPENDENT_RESOURCES"
  echo ""
  echo "Destroy dependent resources first"
  exit 1
fi

# Backup state
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_KEY="backups/${DEPLOYMENT_ID}/${TIMESTAMP}/terraform.tfstate"

echo "Creating backup..."
aws s3 cp \
  "s3://${STATE_BUCKET}/${STATE_KEY}" \
  "s3://${STATE_BUCKET}/${BACKUP_KEY}" \
  --tags "Backup=true" "DeploymentId=${DEPLOYMENT_ID}" "BackupDate=${TIMESTAMP}"

echo "✓ State backed up to: ${BACKUP_KEY}"

# Confirmation
echo ""
echo "⚠ WARNING: This will destroy all resources in deployment: ${DEPLOYMENT_ID}"
echo ""
read -p "Type 'DESTROY' to confirm: " confirm

if [ "$confirm" != "DESTROY" ]; then
  echo "Destruction cancelled"
  exit 0
fi

# Destroy
echo ""
echo "Destroying resources..."
tofu destroy -auto-approve

echo ""
echo "✓ Destruction complete"
echo "  Backup available at: s3://${STATE_BUCKET}/${BACKUP_KEY}"
```

### list-deployed-resources.sh

**Purpose**: Multi-method verification of deployed resources.

**Implementation**:

```bash
#!/bin/bash
# scripts/list-deployed-resources.sh

set -euo pipefail

DEPLOYMENT_ID=$(tofu output -raw deployment_id 2>/dev/null || echo "unknown")

echo "Listing deployed resources for: ${DEPLOYMENT_ID}"
echo ""

# Method 1: Terraform state
echo "=== Method 1: Terraform State ==="
tofu state list

echo ""

# Method 2: Tag-based query
echo "=== Method 2: Tag-based Query ==="
aws resourcegroupstaggingapi get-resources \
  --tag-filters "Key=DeploymentId,Values=${DEPLOYMENT_ID}" \
  --query 'ResourceTagMappingList[].[ResourceARN]' \
  --output text

echo ""

# Method 3: Service-specific queries
echo "=== Method 3: Service-specific Verification ==="

# VPCs
VPCS=$(aws ec2 describe-vpcs \
  --filters "Name=tag:DeploymentId,Values=${DEPLOYMENT_ID}" \
  --query 'Vpcs[].VpcId' \
  --output text)

if [ -n "$VPCS" ]; then
  echo "VPCs: $VPCS"
fi

# S3 Buckets
BUCKETS=$(aws s3api list-buckets \
  --query "Buckets[?contains(Name, '${DEPLOYMENT_ID}')].Name" \
  --output text)

if [ -n "$BUCKETS" ]; then
  echo "S3 Buckets: $BUCKETS"
fi

echo ""
echo "✓ Resource listing complete"
```

---

## Development Environment

### Native Development Approach

This architecture uses native development environments where all tools run directly on the host system.

**Benefits**:

- Direct access to host authentication (AWS, GitHub)
- No architecture compatibility issues
- Simpler troubleshooting and debugging
- Faster iteration cycles
- Works with existing IDE configurations

### Required Tools

**All Platforms**:

- Bash 4+
- AWS CLI v2
- OpenTofu CLI
- GitHub CLI
- jq (JSON processor)

### Installation

**macOS**:

```bash
brew install bash awscli opentofu gh jq
```

**Linux (Ubuntu/Debian)**:

```bash
apt-get install bash awscli jq
# Install OpenTofu and GitHub CLI separately
```

**Windows**:

- Use WSL2 with Ubuntu
- Install tools via Linux package managers

---

## Tagging Strategy

### Standard Tags

All resources must include these tags:

```hcl
tags = {
  Project      = "vpc-foundation"           # Hard-coded per project
  Environment  = "dev"                      # Required input
  DeploymentId = "vpc-foundation-dev"       # From deployment-context
  Owner        = "platform-team"            # Required input (validated)
  AccountId    = "123456789012"             # Discovered via data source
  Region       = "us-east-1"                # Discovered via data source
  DeployedBy   = "arn:aws:iam::..."         # Discovered via data source
  ManagedBy    = "opentofu"                 # Hard-coded
}
```

### Tag Definitions

- **Project**: Identifies which infrastructure project manages the resource
- **Environment**: Deployment environment (dev/staging/prod) - validated
- **DeploymentId**: Unique deployment identifier - enables multi-deployment tracking
- **Owner**: Team or individual responsible - must be customized
- **AccountId**: AWS Account ID - automatic discovery
- **Region**: AWS Region - automatic discovery
- **DeployedBy**: IAM role ARN that deployed the resource - automatic discovery
- **ManagedBy**: IaC tool - hard-coded as "opentofu"

### Validation

**Terraform validation** (in tagging module):

```hcl
variable "owner" {
  type    = string
  default = "CHANGE_ME"
  
  validation {
    condition     = var.owner != "CHANGE_ME"
    error_message = "Owner must be customized (cannot be 'CHANGE_ME')"
  }
}

variable "environment" {
  type = string
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod"
  }
}
```

**Script validation** (in verify-prerequisites.sh):

```bash
check_tag_defaults() {
  if grep -q "CHANGE_ME" terraform.tfvars 2>/dev/null; then
    echo "✗ Default tag values detected in terraform.tfvars"
    FAILURES+=("Tag defaults not customized")
    return 1
  fi
  echo "✓ No default tag values detected"
  return 0
}
```

**Rationale**: Defense in depth - both Terraform and script validation ensure defaults never slip through.

### Cost Allocation

Tags are cost-allocation-ready but require manual activation:

```bash
# Enable cost allocation tags in AWS Billing Console
aws ce update-cost-allocation-tags-status \
  --cost-allocation-tags-status \
    TagKey=Project,Status=Active \
    TagKey=Environment,Status=Active \
    TagKey=DeploymentId,Status=Active \
    TagKey=Owner,Status=Active
```

**Note**: Cost allocation tag activation is not automated. Enable manually in AWS Billing Console after first deployment.

---

## Security Specifications

### Principle of Least Privilege (PoLP)

**Architecture approach**:

- Project 3 (Deployment Roles) acts as authorization boundary
- Application projects cannot create or modify IAM roles
- Each project has minimum permissions for its resource scope
- Centralized role management prevents privilege escalation

**Anti-pattern avoided**: Self-managed deployment roles where projects control their own authorization boundaries.

### No Sensitive Data in Repositories

**Public repository safe items**:

- Resource configurations
- Module definitions
- Documentation
- Example variable files (`.tfvars.example`)
- Scripts

**Excluded from repositories** (`.gitignore`):

```
# Terraform
terraform.tfvars
.terraform/
*.tfstate
*.tfstate.backup
.terraform.lock.hcl

# Sensitive
*.pem
*.key
.env
.aws/

# OS
.DS_Store
Thumbs.db
```

**Sensitive data injection**:

- Environment variables via GitHub Actions secrets
- AWS data sources for discoverable values
- GitHub CLI for repository discovery
- Parameter Store for cross-project references

### OIDC Trust Policy Conditions

All deployment roles require:

```json
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:USERNAME/REPO-NAME:*"
    }
  }
}
```

This restricts role assumption to specific GitHub repositories.

### GitHub Owner Detection

Automatically detect user vs organization:

```bash
GITHUB_USER=$(gh api user --jq .login)
OWNER_TYPE=$(gh api user --jq .type)  # "User" or "Organization"
```

Use in OIDC trust policies:

```hcl
data "external" "github_owner" {
  program = ["bash", "-c", "gh api user --jq '{login: .login, type: .type}'"]
}

locals {
  github_owner = data.external.github_owner.result.login
  repo_path    = "repo:${local.github_owner}/${var.project_name}:*"
}
```

---

## GitHub Secrets Management

### Automated Setup Script

**Location**: `shared-modules/scripts/setup-project-secrets.sh`

**Purpose**: Automate GitHub secrets creation with validation.

**Implementation**:

```bash
#!/bin/bash
# shared-modules/scripts/setup-project-secrets.sh

set -euo pipefail

PROJECT_NAME=$1
ENVIRONMENT=${2:-}

# Build deployment ID
if [ -n "$ENVIRONMENT" ]; then
  DEPLOYMENT_ID="${PROJECT_NAME}-${ENVIRONMENT}"
else
  DEPLOYMENT_ID="${PROJECT_NAME}"
fi

echo "Setting up GitHub secrets for: ${DEPLOYMENT_ID}"

# Fetch from Parameter Store
echo "Fetching values from Parameter Store..."
ROLE_ARN=$(aws ssm get-parameter \
  --name "/terraform/deployment-roles/${DEPLOYMENT_ID}-role-arn" \
  --query 'Parameter.Value' \
  --output text 2>/dev/null || {
  echo "✗ Failed to fetch role ARN"
  echo "  Expected: /terraform/deployment-roles/${DEPLOYMENT_ID}-role-arn"
  exit 1
})

BUCKET=$(aws ssm get-parameter \
  --name "/terraform/foundation/s3-state-bucket" \
  --query 'Parameter.Value' \
  --output text 2>/dev/null || {
  echo "✗ Failed to fetch S3 bucket"
  exit 1
})

TABLE=$(aws ssm get-parameter \
  --name "/terraform/foundation/dynamodb-lock-table" \
  --query 'Parameter.Value' \
  --output text 2>/dev/null || {
  echo "✗ Failed to fetch DynamoDB table"
  exit 1
})

echo "✓ Retrieved all values from Parameter Store"

# Determine GitHub repo
GITHUB_USER=$(gh api user --jq .login)
REPO="${GITHUB_USER}/${PROJECT_NAME}"

echo "Setting secrets in GitHub repo: ${REPO}"

# Set secrets
gh secret set AWS_DEPLOYMENT_ROLE_ARN --repo "$REPO" --body "$ROLE_ARN" || {
  echo "✗ Failed to set AWS_DEPLOYMENT_ROLE_ARN"
  exit 1
}

gh secret set TF_STATE_BUCKET --repo "$REPO" --body "$BUCKET" || {
  echo "✗ Failed to set TF_STATE_BUCKET"
  exit 1
}

gh secret set TF_STATE_DYNAMODB_TABLE --repo "$REPO" --body "$TABLE" || {
  echo "✗ Failed to set TF_STATE_DYNAMODB_TABLE"
  exit 1
}

echo "✓ All secrets set successfully"

# Validate role assumption
echo "Validating role assumption..."
aws sts assume-role \
  --role-arn "$ROLE_ARN" \
  --role-session-name "validation-test" \
  --duration-seconds 900 \
  >/dev/null 2>&1 && {
  echo "✓ Successfully validated role assumption"
} || {
  echo "⚠ Warning: Could not assume role (may require GitHub OIDC context)"
  echo "  This is expected if running locally"
}

echo ""
echo "✓ Setup complete for ${DEPLOYMENT_ID}"
echo "  Role ARN: ${ROLE_ARN}"
echo "  State Bucket: ${BUCKET}"
echo "  Lock Table: ${TABLE}"
```

### Usage

```bash
# From shared-modules repository
./scripts/setup-project-secrets.sh vpc-foundation dev
./scripts/setup-project-secrets.sh eks-platform prod
./scripts/setup-project-secrets.sh hosted-zone  # No environment
```

---

## IAM Policy Refinement (Optional)

### Phase 1: Initial Deployment

Deploy with permissive policies that cover all required resource types.

**Example permissive policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "elasticloadbalancing:*",
        "autoscaling:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### Phase 2: Permission Refinement (Optional)

**Requirements**:

- CloudTrail enabled (may already exist)
- IAM Access Analyzer enabled

**Process**:

1. **Enable CloudTrail** (if not already enabled):

```bash
aws cloudtrail create-trail \
  --name policy-analysis \
  --s3-bucket-name my-cloudtrail-bucket

aws cloudtrail start-logging \
  --name policy-analysis
```

2. **Deploy with permissive role** (already done in Phase 1)

3. **Generate minimal policy** using IAM Access Analyzer:

```bash
# shared-modules/scripts/analyze-iam-policy.sh
#!/bin/bash

ROLE_NAME=$1
START_TIME=$2  # ISO 8601 format

# Generate policy based on CloudTrail
aws accessanalyzer generate-finding-recommendation \
  --analyzer-arn "arn:aws:access-analyzer:us-east-1:ACCOUNT_ID:analyzer/ConsoleAnalyzer" \
  --resource-arn "arn:aws:iam::ACCOUNT_ID:role/${ROLE_NAME}" \
  --start-time "${START_TIME}"

# Wait for generation
sleep 30

# Retrieve generated policy
aws accessanalyzer get-generated-policy \
  --job-id "JOB_ID_FROM_PREVIOUS_COMMAND" \
  --query 'GeneratedPolicyResult.GeneratedPolicies[0].Policy' \
  --output text > minimal-policy.json

echo "✓ Minimal policy generated: minimal-policy.json"
```

4. **Update role** with minimal policy in deployment-roles project

5. **Redeploy** to verify minimal permissions work

**Note**: This is optional. Most users will use permissive policies initially. CloudTrail costs ~$2/100k events + S3 storage.

---

## Deployment Sequence

### Initial Setup

**Prerequisites**:

- AWS account with admin access
- AWS CLI configured
- OpenTofu CLI installed
- GitHub account
- GitHub CLI authenticated

### Step-by-Step Deployment

**1. Deploy Foundation (Project 1)**

```bash
cd terraform-aws-cfn-foundation
./scripts/deploy.sh
```

**Time**: ~5 minutes

**2. Deploy Shared Modules (Project 2)**

```bash
cd terraform-aws-shared-modules
# Tag initial version
git tag v1.0.0
git push origin v1.0.0
```

**Time**: ~2 minutes

**3. Deploy Deployment Roles (Project 3)**

```bash
cd terraform-aws-deployment-roles
./scripts/deploy.sh
```

**Time**: ~5 minutes

**4. Setup GitHub Secrets for Application Project**

```bash
cd terraform-aws-shared-modules
./scripts/setup-project-secrets.sh vpc-foundation dev
```

**Time**: ~1 minute

**5. Deploy Application Project (Project 4+)**

```bash
cd terraform-aws-vpc-foundation
./scripts/deploy.sh
```

**Time**: Varies by project

### Teardown Sequence

**Critical**: Reverse order to prevent orphaned resources.

**1. Destroy all application projects (Project 4+)**

```bash
cd terraform-aws-vpc-foundation
./scripts/destroy.sh
```

**2. Destroy deployment roles (Project 3)**

```bash
cd terraform-aws-deployment-roles
./scripts/destroy.sh
```

**3. Destroy foundation (Project 1)**

```bash
cd terraform-aws-cfn-foundation
./scripts/destroy.sh
```

**Warning**: Foundation destruction deletes state bucket. Ensure all projects destroyed first.

---

## Troubleshooting

### Common Issues

**Issue**: State lock timeout
**Cause**: Previous deployment failed without releasing lock
**Solution**:

```bash
# Manually remove lock from DynamoDB
aws dynamodb delete-item \
  --table-name LOCK_TABLE \
  --key '{"LockID": {"S": "BUCKET/PROJECT/terraform.tfstate"}}'
```

**Issue**: OIDC authentication fails
**Cause**: Trust policy repository condition mismatch
**Solution**: Verify GitHub repository name in deployment role trust policy matches actual repository

**Issue**: Cannot create resources in application project
**Cause**: Insufficient IAM permissions in deployment role
**Solution**: Update role policy in deployment-roles project, redeploy

**Issue**: Backend configuration fails
**Cause**: S3 bucket or DynamoDB table not found
**Solution**: Verify foundation CloudFormation stack deployed successfully, check Parameter Store values

**Issue**: Resource name validation fails
**Cause**: Resource name violates AWS constraints
**Solution**: Fix resource name to use kebab-case (lowercase with hyphens), re-run validation

**Issue**: Tag validation fails
**Cause**: Default tag values not customized
**Solution**: Update terraform.tfvars with actual values, remove "CHANGE_ME" defaults

---

## Documentation Strategy

### Umbrella Project Structure

**Repository**: `aws-terraform-foundation-suite`

**Contents**:

```
aws-terraform-foundation-suite/
├── README.md                    # Overview and quick start
├── docs/
│   ├── architecture.md          # Detailed architecture (this document)
│   ├── deployment-guide.md      # Step-by-step deployment
│   ├── design-decisions.md      # Rationale for choices
│   ├── naming-conventions.md    # Comprehensive naming guide
│   └── troubleshooting.md       # Common issues and solutions
├── diagrams/
│   └── architecture.svg         # Visual representation
└── examples/
    ├── github-actions-workflow.yaml
    └── terraform.tfvars.example
```

### Individual Project READMEs

Each project repository contains:

- Project-specific purpose and scope
- Prerequisites
- Quick start commands
- Link back to umbrella documentation
- Required variables and their sources
- Resources created
- Scripts available

**Template**:

```markdown
# terraform-aws-vpc-foundation

Part of the [AWS Terraform Foundation Suite](https://github.com/USERNAME/aws-terraform-foundation-suite)

## Purpose
Deploys VPC foundation including subnets, route tables, and NAT gateways.

## Prerequisites
- Project 1 (cfn-foundation) deployed
- Project 2 (shared-modules) deployed
- Project 3 (deployment-roles) deployed
- GitHub OIDC configured
- Deployment role ARN from Parameter Store

## Quick Start
See [Deployment Guide](https://github.com/USERNAME/aws-terraform-foundation-suite/blob/main/docs/deployment-guide.md)

## Required Variables
- `environment` - Deployment environment (dev/staging/prod)
- `owner` - Team or individual responsible

## Resources Created
- VPC
- Public/private subnets
- Internet gateway
- NAT gateways
- Route tables

## Scripts
- `scripts/verify-prerequisites.sh` - Validate prerequisites
- `scripts/validate-resource-names.sh` - Validate resource names
- `scripts/deploy.sh` - Deploy infrastructure
- `scripts/destroy.sh` - Destroy infrastructure
- `scripts/list-deployed-resources.sh` - List deployed resources
```

---

## Success Criteria

A successful implementation demonstrates:

1. **No Sensitive Data**: All repositories publicly shareable without exposing credentials or account-specific information
2. **Functional Deployment**: Complete deployment sequence from foundation to application resources works without manual intervention beyond initial CloudFormation deployment
3. **Security Compliance**: Each project operates with minimum necessary permissions
4. **Maintainability**: Clear separation of concerns allows independent project updates
5. **Reproducibility**: Another user can clone repositories and deploy to their AWS account following documentation
6. **Validation**: All scripts include comprehensive error handling and validation
7. **Consistency**: Naming conventions, tagging, and structure consistent across all projects

---

## Document Metadata

**Version**: 12.0
**Date**: 2024-12-03
**Status**: Implementation Ready
**Authors**: Architecture review and refinement
**Changes from v11**:

- Removed container-specific development approach
- Updated to native development environment
- Simplified tooling requirements
- Removed container-specific scripts and configurations
- Streamlined GitHub Actions workflows
- Focused on direct host system execution
- Documented lessons learned from containerization exploration
