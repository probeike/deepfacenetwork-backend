# AWS S3 Bucket Terraform Configuration with Multi-Environment Support

This repository contains a Terraform configuration to deploy an S3 bucket to AWS with support for multiple environments (dev and prod).

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) installed (version 0.12+)
- AWS credentials configured (via environment variables)

## Environment Variables

The following environment variables need to be set:

```
export AWS_ACCESS_KEY_ID="your_access_key"
export AWS_SECRET_ACCESS_KEY="your_secret_key"
export TF_VAR_aws_account_id="your_aws_account_id"
```

For environment-specific deployments, you can also set:

```
export TF_VAR_environment="dev"  # or "prod" for production
```

## 2-Stage Deployment Flow

This project supports a 2-stage deployment flow:

1. **Development Environment (dev)**:
   - Resources are created with a `-dev` suffix
   - Deployed from local machine
   - Default when running Terraform locally

2. **Production Environment (prod)**:
   - Resources are created with a `-prod` suffix
   - Deployed via GitHub Actions
   - Automatically detected when running in GitHub Actions

The environment is determined automatically:
- If running in GitHub Actions, it defaults to "prod"
- If running locally, it defaults to "dev" (or whatever is specified in the TF_VAR_environment variable)

## Usage

### Local Development Deployment

1. Initialize the Terraform configuration:

```
terraform init
```

2. Preview the changes that will be made:

```
terraform plan
```

3. Apply the changes to create the S3 bucket with dev suffix:

```
terraform apply
```

### Production Deployment

Production deployments are handled automatically by GitHub Actions when code is pushed to the main branch.

### Cleanup

When you're done, you can destroy the created resources:

```
terraform destroy
```

## Configuration

- The S3 bucket name is set to "starter-bucket-{env}-{aws_account_id}" in `main.tf`
- The AWS region is set to "us-east-1" in `provider.tf`
- Environment is automatically detected or can be specified via the `environment` variable

You can modify these values as needed for your specific requirements.