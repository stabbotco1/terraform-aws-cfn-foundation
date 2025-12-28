# Bootstrap Sequence Flow

Manual user deployment sequence for the foundation project, showing the .env.example configuration pattern.

## Manual Bootstrap Flow

```
Developer    Foundation Repo    Local Machine    AWS Account    Target Repo    Other Projects
    |             |                   |              |             |               |
    |-- Clone foundation repo ------->|              |             |               |
    |             |                   |              |             |               |
    |             |                   |-- aws configure            |               |
    |             |                   |   (admin credentials)      |               |
    |             |                   |              |             |               |
    |             |                   |-- cp .env.example .env     |               |
    |             |                   |-- edit .env (account ID)   |               |
    |             |                   |              |             |               |
    |             |                   |-- ./scripts/deploy.sh ---->|               |
    |             |                   |              |             |               |
    |             |                   |              |-- Create OIDC provider     |
    |             |                   |              |-- Create S3/DynamoDB       |
    |             |                   |              |-- Create IAM roles         |
    |             |                   |              |-- Create SSM parameters    |
    |             |                   |              |             |               |
    |             |                   |              |             |               |
    |-- Later: setup other projects -------------------------------->|               |
    |             |                   |              |             |               |
    |             |                   |              |             |-- cp .env.example .env
    |             |                   |              |             |-- edit .env (account ID)
    |             |                   |              |             |-- trigger workflow
    |             |                   |              |             |               |
    |             |                   |              |             |-- Read .env for account ID
    |             |                   |              |             |-- OIDC auth works ✓
    |             |                   |              |             |-- Deploy project
```

## Key Changes from Automated Approach

### Before (GitHub Variables)
- Foundation automatically set GitHub variables across repositories
- Other projects used `vars.AWS_ACCOUNT_ID` from GitHub
- Required GitHub organization or complex variable management

### After (Manual .env Pattern)
- Each project manages its own `.env` file with account ID
- Foundation deployment only creates AWS infrastructure
- Standard `.env.example` pattern across all projects
- No cross-repository dependencies or GitHub variable management

## Bootstrap Commands

```bash
# One-time setup
aws configure
gh auth login  # Only needed for target repository validation

# Foundation deployment
git clone https://github.com/stephenabbot/foundation-terraform-bootstrap.git
cd foundation-terraform-bootstrap
cp .env.example .env
# Edit .env with your AWS account ID

./scripts/verify-prerequisites.sh
./scripts/deploy.sh

# Verification
./scripts/list-deployed-resources.sh
```

## Other Project Setup

Each consuming project follows the same pattern:

```bash
# In each consuming project
cp .env.example .env
# Edit .env with the same AWS account ID
# Project workflows read account ID from .env
```

## Configuration Management Benefits

- **Security**: Real account IDs never committed to git
- **Simplicity**: No GitHub variable coordination required  
- **Cost-effective**: No GitHub organization dependency
- **Standard**: Follows common development practices
- **Validation**: Scripts verify .env matches current AWS session

This eliminates the bootstrap coordination problem through consistent manual configuration rather than automated cross-repository variable management.
