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

echo -e "${YELLOW}S3 Bucket Cleanup Script${NC}"
echo "This script will clean up AWS resources while preserving the S3 bucket"
echo

# Interactive confirmation for local runs
if [ "$CI" != "true" ]; then
  echo -e "${RED}WARNING: This will clean up AWS resources (except the S3 bucket).${NC}"
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

# Get S3 bucket name
if [ -z "$S3_BUCKET_NAME" ]; then
  echo "S3_BUCKET_NAME not set, getting from Terraform output..."
  S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
fi

# Manual cleanup of any resources that might not be handled by Terraform destroy
echo -e "${GREEN}Performing manual cleanup of AWS resources...${NC}"

# Check for and clean up any EKS clusters
echo "Checking for EKS clusters..."
EKS_CLUSTERS=$(aws eks list-clusters --region $AWS_REGION --query 'clusters[?contains(@, `ai-agent-cluster-'$ENVIRONMENT'`)]' --output text)
if [ -n "$EKS_CLUSTERS" ]; then
  for CLUSTER in $EKS_CLUSTERS; do
    echo "Found EKS cluster: $CLUSTER. Cleaning up..."
    
    # Update kubeconfig to connect to the cluster
    aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER
    
    # Delete all services with LoadBalancers first to ensure proper cleanup
    echo "Deleting Kubernetes services..."
    kubectl get services --all-namespaces -o json | jq -r '.items[] | select(.spec.type == "LoadBalancer") | .metadata.namespace + " " + .metadata.name' | while read -r ns name; do
      echo "Deleting service $name in namespace $ns"
      kubectl delete service $name -n $ns --ignore-not-found=true
    done
    
    # Delete all deployments
    echo "Deleting Kubernetes deployments..."
    kubectl delete deployments --all --all-namespaces --ignore-not-found=true
    
    # Wait for resources to be deleted
    echo "Waiting for Kubernetes resources to be deleted..."
    sleep 30
    
    # Delete the EKS cluster using AWS CLI
    echo "Deleting EKS cluster: $CLUSTER"
    aws eks delete-cluster --name $CLUSTER --region $AWS_REGION
    
    # Wait for cluster deletion to complete
    echo "Waiting for EKS cluster deletion to complete..."
    aws eks wait cluster-deleted --name $CLUSTER --region $AWS_REGION
  done
fi

# Check for and clean up any ECR repositories
echo "Checking for ECR repositories..."
ECR_REPOS=$(aws ecr describe-repositories --region $AWS_REGION --query 'repositories[?contains(repositoryName, `ai-agent-app-'$ENVIRONMENT'`)].repositoryName' --output text)
if [ -n "$ECR_REPOS" ]; then
  for REPO in $ECR_REPOS; do
    echo "Found ECR repository: $REPO. Cleaning up..."
    
    # Delete all images in the repository
    echo "Deleting all images in repository $REPO..."
    IMAGE_IDS=$(aws ecr list-images --repository-name $REPO --region $AWS_REGION --query 'imageIds[*]' --output json)
    
    if [ "$IMAGE_IDS" != "[]" ]; then
      aws ecr batch-delete-image --repository-name $REPO --region $AWS_REGION --image-ids "$IMAGE_IDS"
    fi
    
    # Delete the repository
    echo "Deleting ECR repository: $REPO"
    aws ecr delete-repository --repository-name $REPO --region $AWS_REGION --force
  done
fi

# Check for and clean up any API Gateway APIs
echo "Checking for API Gateway APIs..."
API_IDS=$(aws apigatewayv2 get-apis --region $AWS_REGION --query 'Items[?contains(Name, `ai-agent-api-'$ENVIRONMENT'`)].ApiId' --output text)
if [ -n "$API_IDS" ]; then
  for API_ID in $API_IDS; do
    echo "Found API Gateway: $API_ID. Cleaning up..."
    
    # Delete all routes
    echo "Deleting API Gateway routes..."
    ROUTES=$(aws apigatewayv2 get-routes --api-id $API_ID --region $AWS_REGION --query 'Items[*].RouteId' --output text)
    for ROUTE_ID in $ROUTES; do
      aws apigatewayv2 delete-route --api-id $API_ID --route-id $ROUTE_ID --region $AWS_REGION
    done
    
    # Delete all integrations
    echo "Deleting API Gateway integrations..."
    INTEGRATIONS=$(aws apigatewayv2 get-integrations --api-id $API_ID --region $AWS_REGION --query 'Items[*].IntegrationId' --output text)
    for INTEGRATION_ID in $INTEGRATIONS; do
      aws apigatewayv2 delete-integration --api-id $API_ID --integration-id $INTEGRATION_ID --region $AWS_REGION
    done
    
    # Delete the API
    echo "Deleting API Gateway: $API_ID"
    aws apigatewayv2 delete-api --api-id $API_ID --region $AWS_REGION
  done
fi

# Check for and clean up any VPCs
echo "Checking for VPCs..."
VPC_IDS=$(aws ec2 describe-vpcs --region $AWS_REGION --filters "Name=tag:Name,Values=ai-agent-vpc-$ENVIRONMENT" --query 'Vpcs[*].VpcId' --output text)
if [ -n "$VPC_IDS" ]; then
  for VPC_ID in $VPC_IDS; do
    echo "Found VPC: $VPC_ID. Cleaning up..."
    
    # Delete all NAT Gateways
    NAT_GATEWAY_IDS=$(aws ec2 describe-nat-gateways --region $AWS_REGION --filter "Name=vpc-id,Values=$VPC_ID" --query 'NatGateways[*].NatGatewayId' --output text)
    for NAT_ID in $NAT_GATEWAY_IDS; do
      echo "Deleting NAT Gateway: $NAT_ID"
      aws ec2 delete-nat-gateway --nat-gateway-id $NAT_ID --region $AWS_REGION
    done
    
    # Wait for NAT Gateways to be deleted
    if [ -n "$NAT_GATEWAY_IDS" ]; then
      echo "Waiting for NAT Gateways to be deleted..."
      sleep 60
    fi
    
    # Delete all Internet Gateways
    IGW_IDS=$(aws ec2 describe-internet-gateways --region $AWS_REGION --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[*].InternetGatewayId' --output text)
    for IGW_ID in $IGW_IDS; do
      echo "Detaching and deleting Internet Gateway: $IGW_ID"
      aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $AWS_REGION
      aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID --region $AWS_REGION
    done
    
    # Delete all Subnets
    SUBNET_IDS=$(aws ec2 describe-subnets --region $AWS_REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text)
    for SUBNET_ID in $SUBNET_IDS; do
      echo "Deleting Subnet: $SUBNET_ID"
      aws ec2 delete-subnet --subnet-id $SUBNET_ID --region $AWS_REGION
    done
    
    # Delete all Security Groups (except default)
    SG_IDS=$(aws ec2 describe-security-groups --region $AWS_REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
    for SG_ID in $SG_IDS; do
      echo "Deleting Security Group: $SG_ID"
      aws ec2 delete-security-group --group-id $SG_ID --region $AWS_REGION
    done
    
    # Delete all Route Tables (except main)
    RT_IDS=$(aws ec2 describe-route-tables --region $AWS_REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[?Associations[?Main!=`true`]].RouteTableId' --output text)
    for RT_ID in $RT_IDS; do
      # First, disassociate all subnet associations
      ASSOC_IDS=$(aws ec2 describe-route-tables --region $AWS_REGION --route-table-ids $RT_ID --query 'RouteTables[*].Associations[?Main!=`true`].RouteTableAssociationId' --output text)
      for ASSOC_ID in $ASSOC_IDS; do
        echo "Disassociating Route Table Association: $ASSOC_ID"
        aws ec2 disassociate-route-table --association-id $ASSOC_ID --region $AWS_REGION
      done
      
      echo "Deleting Route Table: $RT_ID"
      aws ec2 delete-route-table --route-table-id $RT_ID --region $AWS_REGION
    done
    
    # Delete the VPC
    echo "Deleting VPC: $VPC_ID"
    aws ec2 delete-vpc --vpc-id $VPC_ID --region $AWS_REGION
  done
fi

# Step 4: Run Terraform apply to ensure only the S3 bucket exists
echo -e "${GREEN}Running Terraform apply to ensure only the S3 bucket exists...${NC}"

# Select the appropriate workspace
if [ "$ENVIRONMENT" == "prod" ]; then
  terraform workspace select prod || terraform workspace new prod
else
  terraform workspace select default
fi

# Apply the Terraform configuration (which now only includes the S3 bucket)
terraform apply -auto-approve

echo -e "${GREEN}Cleanup completed successfully!${NC}"
echo "All AWS resources have been removed except for the S3 bucket: $S3_BUCKET_NAME"