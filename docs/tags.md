# Resource Tags

All resources deployed by this foundation include comprehensive tags for cost allocation, ownership tracking, and resource management.

## Standard Tags Applied

- **AccountId**: AWS account ID where resources are deployed
- **AccountAlias**: AWS account alias (if configured)
- **CostCenter**: Cost center for billing allocation (from TAG_COST_CENTER)
- **DeploymentRole**: IAM role ARN used for deployment
- **Environment**: Environment designation (from TAG_ENVIRONMENT)
- **ManagedBy**: Management tool (CloudFormation)
- **Owner**: Resource owner (from TAG_OWNER)
- **Project**: Project name derived from repository
- **Region**: AWS region for regional resources, or "na" for global resources
- **Repository**: Full git repository URL

## Resource-Specific Tags

### OIDC Provider

- **OidcProvider**: Provider type (github, gitlab, bitbucket)

### Deployment Role

- **TargetRepository**: Target repository for deployment roles project

## Tag Configuration

Tags are configured through the .env file:

- TAG_COST_CENTER: Cost center for billing allocation
- TAG_ENVIRONMENT: Environment (prd, stg, tst, dev)
- TAG_OWNER: Resource owner identifier

Repository and deployment metadata are automatically detected during deployment.
