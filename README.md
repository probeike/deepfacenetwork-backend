# S3 Bucket Deployment on AWS

This repository contains a simplified solution for deploying only an S3 bucket on AWS. All other resources (ECR repository, EKS cluster, Kubernetes deployments, API Gateway, etc.) have been removed to reduce costs and complexity.

## Architecture Overview

The deployment now only includes:

```
S3 Bucket
```

Components:
- **Terraform Infrastructure**: S3 Bucket only

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) installed (version 1.0+)
- [AWS CLI](https://aws.amazon.com/cli/) installed and configured
- AWS credentials configured with appropriate permissions

## Environment Variables

The following environment variables need to be set:

```bash
export AWS_ACCESS_KEY_ID="your_access_key"
export AWS_SECRET_ACCESS_KEY="your_secret_key"
export TF_VAR_aws_account_id="your_aws_account_id"
```

## Deployment Steps

### Terraform Infrastructure Setup

1. Initialize the Terraform configuration:

```bash
./setup-dev.sh  # For development environment
# OR
terraform init   # Manual initialization
```

2. Preview the changes that will be made:

```bash
terraform plan
```

3. Apply the Terraform configuration to create the S3 bucket:

```bash
terraform apply
```

This will create:
- S3 bucket with environment-specific naming

### Automated Deployment

For convenience, you can use the provided deployment script:

```bash
./deploy.sh
```

This script will:
1. Apply the Terraform configuration to create/update the S3 bucket
2. Output the S3 bucket name

## Project Structure

```
.
├── main.tf                 # Main Terraform configuration (S3 bucket only)
├── provider.tf             # Terraform provider configuration
├── setup-dev.sh            # Development setup script
├── deploy.sh               # Deployment script
└── cleanup.sh              # Cleanup script for removing AWS resources while preserving the S3 bucket
```

## Multi-Environment Support

This project supports multiple environments (dev and prod) using Terraform workspaces:

- **Development Environment (dev)**:
  - Resources are created with a `-dev` suffix
  - Default when running Terraform locally

- **Production Environment (prod)**:
  - Resources are created with a `-prod` suffix
  - Automatically deployed via GitHub Actions workflow
  - Can be manually selected with `terraform workspace select prod`

## Environment-Aware Deployment Script

The project includes an environment-aware deployment script (`deploy.sh`) that can be used both locally and in CI/CD pipelines. The script:

1. Detects whether it's running locally or in GitHub Actions
2. Uses environment variables if they're set, otherwise falls back to Terraform outputs
3. Skips interactive prompts when running in CI
4. Handles the S3 bucket deployment process

### Using the Script Locally

```bash
# Set optional environment variables (or let the script use Terraform outputs)
export AWS_REGION=us-east-1

# Run the script
./deploy.sh
```

### Using the Script in CI/CD

The script automatically detects when it's running in GitHub Actions and adjusts its behavior accordingly:
- Skips interactive prompts
- Uses environment variables passed from the workflow
- Exports results back to GitHub Actions environment variables

## Automated Production Deployment

This project includes a GitHub Actions workflow (`.github/workflows/deploy.yml`) that automatically deploys the S3 bucket to the production environment when changes are pushed to the main branch. The workflow:

1. Sets up Terraform and applies the infrastructure configuration
2. Gets the necessary outputs from Terraform
3. Runs the environment-aware deployment script

To use this automated deployment:

1. Set up the following GitHub repository secrets:
   - `AWS_ACCESS_KEY_ID`: Your AWS access key
   - `AWS_SECRET_ACCESS_KEY`: Your AWS secret key
   - `AWS_ACCOUNT_ID`: Your AWS account ID

2. Push changes to the main branch or manually trigger the workflow from the GitHub Actions tab.

## Cleanup

The cleanup script has been modified to preserve the S3 bucket while removing any other AWS resources that might exist:

```bash
./cleanup.sh
```

This script will:
1. Check for and clean up any EKS clusters
2. Check for and clean up any ECR repositories
3. Check for and clean up any API Gateway APIs
4. Check for and clean up any VPCs and related resources
5. Run Terraform apply to ensure only the S3 bucket exists

The script is environment-aware and will:
- Detect whether it's running locally or in GitHub Actions
- Prompt for confirmation when run locally (skipped in CI)
- Clean up resources for the current environment (dev or prod)

### Automated Cleanup via GitHub Actions

For production environments, you can use the provided GitHub Actions workflow to clean up AWS resources:

1. Go to the "Actions" tab in your GitHub repository
2. Select the "Cleanup AWS Resources (Preserve S3 Bucket)" workflow
3. Click "Run workflow"
4. Select the environment to clean up (dev or prod)
5. Type "yes-cleanup-resources" in the confirmation field
6. Click "Run workflow"

This workflow uses the same cleanup script but runs it in a CI environment with the appropriate workspace selected.

## Security Considerations

- Consider enabling S3 bucket encryption for sensitive data
- Review S3 bucket policies and access controls regularly
- Use IAM roles and policies with least privilege principles