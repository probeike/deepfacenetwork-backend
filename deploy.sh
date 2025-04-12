#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect if running in GitHub Actions
if [ "$GITHUB_ACTIONS" == "true" ]; then
  echo "Running inside GitHub Actions"
  CI=true
else
  echo "Running locally in interactive mode"
  CI=false
fi

echo -e "${YELLOW}S3 Bucket Deployment Script${NC}"
echo "This script will deploy only the S3 bucket to your AWS environment"
echo

# Interactive confirmation for local runs
if [ "$CI" != "true" ]; then
  echo -e "${YELLOW}This will deploy the S3 bucket to your AWS environment.${NC}"
  echo -e "${YELLOW}Press Ctrl+C to cancel or wait 5 seconds to continue...${NC}"
  sleep 5
fi

# Check if required tools are installed (skip in CI environment)
if [ "$CI" != "true" ]; then
  # Check if AWS CLI is installed
  if ! command -v aws &> /dev/null; then
      echo "AWS CLI is not installed. Please install it first."
      exit 1
  fi
fi

# Set AWS region
AWS_REGION=${AWS_REGION:-"us-east-1"}

# Get AWS account ID if not already set
if [ -z "$AWS_ACCOUNT_ID" ]; then
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
fi

# Get required variables from environment or Terraform outputs
echo -e "${GREEN}Getting deployment variables...${NC}"

# Get S3 bucket name
if [ -z "$S3_BUCKET_NAME" ]; then
  echo "S3_BUCKET_NAME not set, getting from Terraform output..."
  S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)
fi

echo "S3 Bucket Name: $S3_BUCKET_NAME"

# Apply Terraform to create/update the S3 bucket
echo -e "${GREEN}Applying Terraform to create/update the S3 bucket...${NC}"
terraform apply -auto-approve

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo "Your S3 bucket is now deployed and accessible at:"
echo "S3 Bucket: $S3_BUCKET_NAME"

# Export variables for GitHub Actions if running in CI
if [ "$GITHUB_ACTIONS" == "true" ]; then
  echo "S3_BUCKET_NAME=$S3_BUCKET_NAME" >> $GITHUB_ENV
fi