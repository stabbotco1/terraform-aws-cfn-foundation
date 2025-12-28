# Troubleshooting

## Stack Creation Failures

If the CloudFormation stack fails to create, check the AWS CloudFormation console for detailed error messages. Common issues include:

- Insufficient IAM permissions for the deploying user or role
- Service quota limits reached for S3 buckets or DynamoDB tables
- Existing resources with conflicting names in the account and region
- Invalid parameter values in the .env configuration file

Review the CloudFormation events tab to identify which resource failed and why. The deployment script includes rollback handling, so failed deployments will clean up partial resources automatically.

## OIDC Provider Issues

OIDC provider creation requires valid thumbprints for the identity provider. The deployment script automatically configures thumbprints for GitHub, GitLab, and Bitbucket based on your git remote origin. If OIDC provider creation fails:

- Verify your git remote origin URL is correctly formatted
- Ensure the remote is one of the supported providers
- Check that the OIDC provider does not already exist in your account
- Confirm your AWS account has permissions to create OIDC providers

Only one OIDC provider per identity provider URL can exist in an AWS account. If you need to update an existing provider, delete it first or modify the stack.

## State Bucket Access

If consuming projects cannot access the state bucket, verify:

- SSM parameters exist at /terraform/foundation/s3-state-bucket and /terraform/foundation/dynamodb-lock-table
- The IAM role or user has permissions to read SSM parameters in us-east-1
- The state bucket policy allows access from the consuming project's IAM role
- The DynamoDB table exists and has the correct permissions

Use the list-deployed-resources script to confirm all foundation resources are deployed and accessible. Check IAM policies on consuming project roles to ensure they include S3 and DynamoDB permissions for the backend resources.
