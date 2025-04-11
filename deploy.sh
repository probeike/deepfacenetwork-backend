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

echo -e "${YELLOW}AI Agent Deployment Script${NC}"
echo "This script will deploy the AI Agent application to your EKS cluster"
echo

# Interactive confirmation for local runs
if [ "$CI" != "true" ]; then
  echo -e "${YELLOW}This will deploy the application to your AWS environment.${NC}"
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

  # Check if kubectl is installed
  if ! command -v kubectl &> /dev/null; then
      echo "kubectl is not installed. Please install it first."
      exit 1
  fi

  # Check if Docker is installed
  if ! command -v docker &> /dev/null; then
      echo "Docker is not installed. Please install it first."
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

# Get cluster name
if [ -z "$CLUSTER_NAME" ]; then
  echo "CLUSTER_NAME not set, getting from Terraform output..."
  CLUSTER_NAME=$(terraform output -raw cluster_name)
fi

# Get ECR repository URL
if [ -z "$ECR_REPOSITORY_URL" ]; then
  echo "ECR_REPOSITORY_URL not set, getting from Terraform output..."
  ECR_REPOSITORY_URL=$(terraform output -raw ecr_repository_url)
fi

# Get API Gateway endpoint
if [ -z "$API_GATEWAY_ENDPOINT" ]; then
  echo "API_GATEWAY_ENDPOINT not set, getting from Terraform output..."
  API_GATEWAY_ENDPOINT=$(terraform output -raw api_gateway_endpoint)
fi

# Get API ID from API Gateway endpoint
if [ -z "$API_ID" ]; then
  API_ID=$(echo $API_GATEWAY_ENDPOINT | cut -d'/' -f3 | cut -d'.' -f1)
fi

echo "Cluster Name: $CLUSTER_NAME"
echo "ECR Repository URL: $ECR_REPOSITORY_URL"
echo "API Gateway Endpoint: $API_GATEWAY_ENDPOINT"
echo "API ID: $API_ID"

# Update kubeconfig to connect to the EKS cluster
echo -e "${GREEN}Updating kubeconfig for EKS cluster...${NC}"
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# Define deployment name for consistency
DEPLOYMENT_NAME="ai-agent-app"

# Build and push Docker image to ECR
echo -e "${GREEN}Building and pushing Docker image to ECR...${NC}"

# Authenticate Docker to ECR (do this only once)
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPOSITORY_URL

# Determine if we're using Docker Buildx or regular Docker
if command -v docker buildx &> /dev/null; then
  echo "Using Docker Buildx for building the image..."
  
  # Create and use builder if not already present
  docker buildx inspect eks-builder &>/dev/null || docker buildx create --use --name eks-builder
  docker buildx use eks-builder
  
  # Build and push directly with Buildx
  cd app
  docker buildx build --platform linux/amd64 \
    --push \
    -t $ECR_REPOSITORY_URL:latest \
    -t $ECR_REPOSITORY_URL:$(date +%Y%m%d%H%M%S) \
    .
  cd ..
else
  # Standard Docker build process
  cd app
  
  # Hardcode platform for Mac users
  export DOCKER_DEFAULT_PLATFORM=linux/amd64
  
  # Build the Docker image
  docker build -t ai-agent-app:latest .
  
  # Tag the image for ECR
  docker tag ai-agent-app:latest $ECR_REPOSITORY_URL:latest
  
  # Push the image to ECR
  docker push $ECR_REPOSITORY_URL:latest
  
  cd ..
fi

# Update Kubernetes deployment manifest with ECR repository URL
echo -e "${GREEN}Updating Kubernetes deployment manifest...${NC}"
sed -i.bak "s|\${ECR_REPOSITORY_URL}|$ECR_REPOSITORY_URL|g" kubernetes/deployment.yaml
rm -f kubernetes/deployment.yaml.bak

# Apply Kubernetes manifests
echo -e "${GREEN}Applying Kubernetes manifests...${NC}"
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml

# Wait for the deployment to be ready
echo -e "${GREEN}Waiting for deployment to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/$DEPLOYMENT_NAME

# Get the LoadBalancer URL
echo -e "${GREEN}Getting LoadBalancer URL...${NC}"
LB_HOSTNAME=""
ATTEMPTS=0
MAX_ATTEMPTS=30

while [ -z "$LB_HOSTNAME" ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
  echo "Waiting for LoadBalancer hostname... Attempt $((ATTEMPTS+1))/$MAX_ATTEMPTS"
  LB_HOSTNAME=$(kubectl get service ai-agent-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  if [ -z "$LB_HOSTNAME" ]; then
    sleep 10
    ATTEMPTS=$((ATTEMPTS+1))
  fi
done

if [ -z "$LB_HOSTNAME" ]; then
  echo "Failed to get LoadBalancer hostname after $MAX_ATTEMPTS attempts"
  exit 1
fi

echo "LoadBalancer Hostname: $LB_HOSTNAME"

# Create API Gateway integration with the LoadBalancer
echo -e "${GREEN}Creating API Gateway integration...${NC}"

# Create the integration
INTEGRATION_ID=$(aws apigatewayv2 create-integration \
  --api-id $API_ID \
  --integration-type HTTP_PROXY \
  --integration-method ANY \
  --integration-uri http://$LB_HOSTNAME \
  --payload-format-version 1.0 \
  --query IntegrationId \
  --output text)

echo "Integration ID: $INTEGRATION_ID"

# Create the route
ROUTE_ID=$(aws apigatewayv2 create-route \
  --api-id $API_ID \
  --route-key 'GET /' \
  --target "integrations/$INTEGRATION_ID" \
  --query RouteId \
  --output text)

echo "Route ID: $ROUTE_ID"

# Test the API
echo -e "${GREEN}Testing the API...${NC}"
echo "API Gateway Endpoint: $API_GATEWAY_ENDPOINT"
echo "Testing direct LoadBalancer endpoint..."
curl -s --fail http://$LB_HOSTNAME || echo "❌ LoadBalancer test failed"
echo
echo "Testing API Gateway endpoint..."
curl -s --fail $API_GATEWAY_ENDPOINT || echo "❌ API Gateway test failed"
echo

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo "Your AI Agent application is now deployed and accessible at:"
echo "LoadBalancer URL: http://$LB_HOSTNAME"
echo "API Gateway URL: $API_GATEWAY_ENDPOINT"

# Export variables for GitHub Actions if running in CI
if [ "$GITHUB_ACTIONS" == "true" ]; then
  echo "LB_HOSTNAME=$LB_HOSTNAME" >> $GITHUB_ENV
  echo "INTEGRATION_ID=$INTEGRATION_ID" >> $GITHUB_ENV
  echo "ROUTE_ID=$ROUTE_ID" >> $GITHUB_ENV
fi