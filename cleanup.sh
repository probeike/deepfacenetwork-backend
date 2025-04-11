#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Detect if running in GitHub Actions
if [ "$GITHUB_ACTIONS" == "true" ]; then
  echo "Running inside GitHub Actions"
  CI=true
else
  echo "Running locally in interactive mode"
  CI=false
fi

echo -e "${YELLOW}AI Agent Cleanup Script${NC}"
echo "This script will remove all resources created for the AI Agent deployment"
echo

# Interactive confirmation for local runs
if [ "$CI" != "true" ]; then
  echo -e "${RED}WARNING: This will delete all resources created for the AI Agent deployment.${NC}"
  echo -e "${RED}This action is irreversible and will result in data loss.${NC}"
  echo -e "${YELLOW}Are you sure you want to continue? (y/n)${NC}"
  read -r confirmation
  if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
    echo "Cleanup aborted."
    exit 0
  fi
fi

# Set AWS region
AWS_REGION=${AWS_REGION:-"us-east-1"}

# Get required variables from environment or Terraform outputs
echo -e "${GREEN}Getting deployment variables...${NC}"

# Get workspace/environment
if [ -z "$ENVIRONMENT" ]; then
  ENVIRONMENT=$(terraform workspace show)
  if [ "$ENVIRONMENT" == "default" ]; then
    ENVIRONMENT="dev"
  fi
fi

echo "Cleaning up environment: $ENVIRONMENT"

# Get cluster name
if [ -z "$CLUSTER_NAME" ]; then
  echo "CLUSTER_NAME not set, getting from Terraform output..."
  CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
fi

# Get ECR repository URL
if [ -z "$ECR_REPOSITORY_URL" ]; then
  echo "ECR_REPOSITORY_URL not set, getting from Terraform output..."
  ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_url 2>/dev/null || echo "")
fi

# Get API Gateway endpoint
if [ -z "$API_GATEWAY_ENDPOINT" ]; then
  echo "API_GATEWAY_ENDPOINT not set, getting from Terraform output..."
  API_GATEWAY_ENDPOINT=$(terraform output -raw api_gateway_endpoint 2>/dev/null || echo "")
fi

# Get API ID from API Gateway endpoint
if [ -z "$API_ID" ] && [ -n "$API_GATEWAY_ENDPOINT" ]; then
  API_ID=$(echo $API_GATEWAY_ENDPOINT | cut -d'/' -f3 | cut -d'.' -f1)
fi

# Check if kubectl is installed
if command -v kubectl &> /dev/null; then
  KUBECTL_INSTALLED=true
else
  KUBECTL_INSTALLED=false
  echo "kubectl is not installed. Skipping Kubernetes resource cleanup."
fi

# Step 1: Remove Kubernetes resources if kubectl is installed and cluster exists
if [ "$KUBECTL_INSTALLED" == "true" ] && [ -n "$CLUSTER_NAME" ]; then
  echo -e "${GREEN}Updating kubeconfig for EKS cluster...${NC}"
  if aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION &>/dev/null; then
    aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME
    
    echo -e "${GREEN}Removing Kubernetes resources...${NC}"
    kubectl delete service ai-agent-app-service --ignore-not-found=true
    kubectl delete deployment ai-agent-app --ignore-not-found=true
    
    echo "Kubernetes resources removed."
  else
    echo "EKS cluster $CLUSTER_NAME not found. Skipping Kubernetes resource cleanup."
  fi
fi

# Step 2: Remove API Gateway routes and integrations
if [ -n "$API_ID" ]; then
  echo -e "${GREEN}Removing API Gateway routes and integrations...${NC}"
  
  # Get all routes
  ROUTES=$(aws apigatewayv2 get-routes --api-id $API_ID --query 'Items[*].RouteId' --output text 2>/dev/null || echo "")
  
  # Delete each route
  for ROUTE_ID in $ROUTES; do
    echo "Deleting route $ROUTE_ID..."
    aws apigatewayv2 delete-route --api-id $API_ID --route-id $ROUTE_ID
  done
  
  # Get all integrations
  INTEGRATIONS=$(aws apigatewayv2 get-integrations --api-id $API_ID --query 'Items[*].IntegrationId' --output text 2>/dev/null || echo "")
  
  # Delete each integration
  for INTEGRATION_ID in $INTEGRATIONS; do
    echo "Deleting integration $INTEGRATION_ID..."
    aws apigatewayv2 delete-integration --api-id $API_ID --integration-id $INTEGRATION_ID
  done
  
  echo "API Gateway routes and integrations removed."
else
  echo "API Gateway ID not found. Skipping API Gateway cleanup."
fi

# Step 3: Remove ECR repository images
if [ -n "$ECR_REPOSITORY_URL" ]; then
  echo -e "${GREEN}Removing ECR repository images...${NC}"
  
  # Extract repository name from URL
  REPO_NAME=$(echo $ECR_REPOSITORY_URL | cut -d'/' -f2)
  
  # Get all image IDs (by both digest and tag, if present)
  IMAGE_IDS=$(aws ecr list-images --repository-name $REPO_NAME --query 'imageIds[*]' --output json)
  
  if [ "$IMAGE_IDS" != "[]" ]; then
    echo "Deleting all images in ECR repo: $REPO_NAME..."
    aws ecr batch-delete-image \
      --repository-name $REPO_NAME \
      --image-ids "$IMAGE_IDS"
    echo "ECR images deleted."
  else
    echo "No images to delete in ECR."
  fi
else
  echo "ECR repository URL not found. Skipping ECR cleanup."
fi

# Step 4: Destroy Terraform-managed infrastructure
echo -e "${GREEN}Destroying Terraform-managed infrastructure...${NC}"

if [ "$CI" != "true" ]; then
  echo -e "${RED}WARNING: This will destroy all Terraform-managed infrastructure.${NC}"
  echo -e "${YELLOW}Are you sure you want to continue? (y/n)${NC}"
  read -r confirmation
  if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
    echo "Terraform destroy aborted."
    exit 0
  fi
fi

# Select the appropriate workspace
if [ "$ENVIRONMENT" == "prod" ]; then
  terraform workspace select prod || terraform workspace new prod
else
  terraform workspace select default
fi

# Destroy the infrastructure
terraform destroy -auto-approve

echo -e "${GREEN}Cleanup completed successfully!${NC}"
echo "All resources for the AI Agent deployment have been removed."