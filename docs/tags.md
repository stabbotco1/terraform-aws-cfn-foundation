# Resource Tags

All resources deployed by this foundation are tagged according to the ecosystem standard defined in [foundation-standards](https://github.com/stephenabbot/foundation-standards/blob/main/tagging/tagging-standard.md).

## Standard Tags Applied

- **ProjectName**: Repository name derived from git remote
- **ProjectRepository**: Full git repository URL
- **ManagedBy**: Deployment tool (`CloudFormation`)
- **Environment**: Deployment environment (from `TAG_ENVIRONMENT` in config.env)
- **DeployedBy**: IAM principal ARN used for deployment (from AWS STS)
- **AccountAlias**: AWS account alias (from AWS IAM)

## Resource-Specific Tags

### OIDC Provider

- **OidcProvider**: Provider type (github, gitlab, bitbucket)

### Deployment Role

- **TargetRepository**: Target repository for the deployment roles project

## Tag Configuration

`Environment` is sourced from `config.env`:

```bash
TAG_ENVIRONMENT=prd
```

All other tags are computed automatically at deploy time from git metadata and AWS identity.
