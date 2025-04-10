# Basic AWS S3 Bucket Terraform Configuration

This repository contains a basic Terraform configuration to deploy an S3 bucket to AWS.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) installed (version 0.12+)
- AWS credentials configured (via environment variables)

## Environment Variables

The following environment variables need to be set:

```
export AWS_ACCESS_KEY_ID="your_access_key"
export AWS_SECRET_ACCESS_KEY="your_secret_key"
```

## Usage

1. Initialize the Terraform configuration:

```
terraform init
```

2. Preview the changes that will be made:

```
terraform plan
```

3. Apply the changes to create the S3 bucket:

```
terraform apply
```

4. When you're done, you can destroy the created resources:

```
terraform destroy
```

## Configuration

- The S3 bucket name is set to "my-terraform-example-bucket" in `main.tf`
- The AWS region is set to "us-east-1" in `provider.tf`

You can modify these values as needed for your specific requirements.