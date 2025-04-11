# AI Agent Deployment on AWS EKS

This repository contains a complete solution for deploying an AI agent on AWS EKS with API Gateway integration. The deployment includes Terraform infrastructure as code, a Python FastAPI application, Docker containerization, and Kubernetes deployment manifests.

## Architecture Overview

The deployment follows this architecture:

```
User → API Gateway → Kubernetes LoadBalancer → Python App Pod → JSON Response
```

Components:
- **Terraform Infrastructure**: VPC, EKS Cluster, ECR Repository, API Gateway
- **Python Application**: FastAPI-based "Hello World" API
- **Docker Container**: Lightweight Python container
- **Kubernetes Deployment**: EKS-hosted deployment with LoadBalancer service
- **API Gateway**: HTTP API Gateway with integration to the Kubernetes service

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) installed (version 1.0+)
- [AWS CLI](https://aws.amazon.com/cli/) installed and configured
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) installed
- [Docker](https://docs.docker.com/get-docker/) installed
- AWS credentials configured with appropriate permissions

## Environment Variables

The following environment variables need to be set:

```bash
export AWS_ACCESS_KEY_ID="your_access_key"
export AWS_SECRET_ACCESS_KEY="your_secret_key"
export TF_VAR_aws_account_id="your_aws_account_id"
```

## Deployment Steps

### 1. Terraform Infrastructure Setup

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

3. Apply the Terraform configuration to create the infrastructure:

```bash
terraform apply
```

This will create:
- VPC with public subnets
- EKS cluster with a node group
- ECR repository for Docker images
- API Gateway HTTP API

### 2. Build and Push the Docker Image

The deployment script handles this automatically, but you can also do it manually:

```bash
# Get the ECR repository URL
ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_url)

# Authenticate Docker to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REPOSITORY_URL

# Build the Docker image
cd app
docker build -t ai-agent-app:latest .

# Tag the image for ECR
docker tag ai-agent-app:latest $ECR_REPOSITORY_URL:latest

# Push the image to ECR
docker push $ECR_REPOSITORY_URL:latest
```

### 3. Deploy to Kubernetes

The deployment script handles this automatically, but you can also do it manually:

```bash
# Update kubeconfig to connect to the EKS cluster
CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --region us-east-1 --name $CLUSTER_NAME

# Update the deployment manifest with the ECR repository URL
sed -i.bak "s|\${ECR_REPOSITORY_URL}|$ECR_REPOSITORY_URL|g" kubernetes/deployment.yaml

# Apply the Kubernetes manifests
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml

# Get the LoadBalancer URL
kubectl get service ai-agent-app-service
```

### 4. Set Up API Gateway Integration

The deployment script handles this automatically, but you can also do it manually:

```bash
# Get the LoadBalancer hostname
LB_HOSTNAME=$(kubectl get service ai-agent-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Get the API Gateway ID
API_GATEWAY_ENDPOINT=$(terraform output -raw api_gateway_endpoint)
API_ID=$(echo $API_GATEWAY_ENDPOINT | cut -d'/' -f3 | cut -d'.' -f1)

# Create the integration
aws apigatewayv2 create-integration \
  --api-id $API_ID \
  --integration-type HTTP_PROXY \
  --integration-method ANY \
  --integration-uri http://$LB_HOSTNAME \
  --payload-format-version 1.0

# Create the route
aws apigatewayv2 create-route \
  --api-id $API_ID \
  --route-key 'GET /' \
  --target "integrations/$INTEGRATION_ID"
```

### Automated Deployment

For convenience, you can use the provided deployment script to automate the entire process:

```bash
./deploy.sh
```

This script will:
1. Build and push the Docker image to ECR
2. Update the Kubernetes deployment manifest
3. Apply the Kubernetes manifests
4. Set up the API Gateway integration
5. Test the deployment

## Project Structure

```
.
├── app/                    # Python application
│   ├── main.py             # FastAPI application
│   ├── requirements.txt    # Python dependencies
│   └── Dockerfile          # Docker configuration
├── kubernetes/             # Kubernetes manifests
│   ├── deployment.yaml     # Deployment configuration
│   └── service.yaml        # Service configuration
├── main.tf                 # Main Terraform configuration
├── provider.tf             # Terraform provider configuration
├── setup-dev.sh            # Development setup script
├── deploy.sh               # Deployment script
└── cleanup.sh              # Cleanup script for removing all resources
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
4. Handles the complete deployment process from building the Docker image to setting up the API Gateway integration

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

This project includes a GitHub Actions workflow (`.github/workflows/deploy.yml`) that automatically deploys the entire stack to the production environment when changes are pushed to the main branch. The workflow:

1. Sets up Terraform and applies the infrastructure configuration
2. Gets the necessary outputs from Terraform
3. Sets up the required tools (kubectl, Docker Buildx)
4. Runs the environment-aware deployment script to handle the rest of the process

To use this automated deployment:

1. Set up the following GitHub repository secrets:
   - `AWS_ACCESS_KEY_ID`: Your AWS access key
   - `AWS_SECRET_ACCESS_KEY`: Your AWS secret key
   - `AWS_ACCOUNT_ID`: Your AWS account ID

2. Push changes to the main branch or manually trigger the workflow from the GitHub Actions tab.

The workflow will handle the complete deployment process and output the URLs where the application is accessible.

## Cleanup

When you're done with the deployment, you can use the provided cleanup script to remove all created resources:

```bash
./cleanup.sh
```

This script will:
1. Remove Kubernetes resources (deployment, service)
2. Remove API Gateway routes and integrations
3. Remove ECR repository images
4. Destroy all Terraform-managed infrastructure

The script is environment-aware and will:
- Detect whether it's running locally or in GitHub Actions
- Prompt for confirmation when run locally (skipped in CI)
- Clean up resources for the current environment (dev or prod)

**Warning**: This will permanently delete all resources and data. Use with caution.

### Automated Cleanup via GitHub Actions

For production environments, you can use the provided GitHub Actions workflow to clean up all resources:

1. Go to the "Actions" tab in your GitHub repository
2. Select the "Cleanup AI Agent Deployment" workflow
3. Click "Run workflow"
4. Select the environment to clean up (dev or prod)
5. Type "yes-delete-everything" in the confirmation field
6. Click "Run workflow"

This workflow uses the same cleanup script but runs it in a CI environment with the appropriate workspace selected.

### Manual Terraform Cleanup

Alternatively, you can manually destroy just the Terraform-managed resources:

```bash
terraform destroy
```

## Troubleshooting

- **EKS Cluster Access Issues**: Ensure your AWS CLI is configured correctly and you've updated your kubeconfig.
- **Docker Push Failures**: Verify you have authenticated Docker with ECR.
- **API Gateway Integration Issues**: Check that the LoadBalancer has been provisioned and has a valid hostname.

## Security Considerations

- The deployment uses public subnets for simplicity. For production, consider using private subnets with NAT gateways.
- API Gateway is configured to allow all origins (CORS). Restrict this for production.
- Consider implementing IAM roles for service accounts (IRSA) for Kubernetes pods.