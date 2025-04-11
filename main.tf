variable "aws_account_id" {
  type        = string
  description = "The AWS account ID used to make resources globally unique"
}

# We'll use Terraform workspaces instead of this variable
# The workspace name will automatically be "default" (for dev) or "prod"
locals {
  environment = terraform.workspace == "default" ? "dev" : terraform.workspace
  cluster_name = "ai-agent-cluster-${local.environment}"
  
  # VPC CIDR and subnet configuration
  vpc_cidr = "10.0.0.0/16"
  azs      = ["us-east-1a", "us-east-1b"]
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  
  # Tags
  tags = {
    Environment = local.environment
    ManagedBy   = "terraform"
    Project     = "ai-agent"
  }
}

# Keep the starter bucket for reference
resource "aws_s3_bucket" "starter-bucket" {
  bucket = "starter-bucket-${var.aws_account_id}-${local.environment}"
  tags   = local.tags
}

#---------------------------------------------------------------
# VPC Configuration
#---------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = "ai-agent-vpc-${local.environment}"
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = local.public_subnets
  
  # Enable DNS hostnames and support
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  # Enable NAT Gateway for private subnets (if needed)
  # enable_nat_gateway = true
  # single_nat_gateway = true
  
  # Add tags for EKS to discover subnets
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  tags = local.tags
}

#---------------------------------------------------------------
# ECR Repository for Docker Images
#---------------------------------------------------------------

resource "aws_ecr_repository" "app_repository" {
  name                 = "ai-agent-app-${local.environment}"
  force_delete         = true
  image_tag_mutability = "MUTABLE"
  
  image_scanning_configuration {
    scan_on_push = true
  }
  
  tags = local.tags
}

#---------------------------------------------------------------
# EKS Cluster Configuration
#---------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.29"
  
  # Use the VPC and subnets created above
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets
  
  # Cluster access configuration
  cluster_endpoint_public_access = true
  
  # Enable OIDC provider for service accounts
  enable_irsa = true
  
  # EKS Managed Node Group(s)
  eks_managed_node_groups = {
    default_node_group = {
      name = "node-group-${local.environment}"
      
      instance_types = ["t3.medium"]
      
      min_size     = 1
      max_size     = 3
      desired_size = 1
      
      # Use the public subnets
      subnet_ids = module.vpc.public_subnets
    }
  }
  
  # Add tags
  tags = local.tags
}

#---------------------------------------------------------------
# API Gateway Configuration
#---------------------------------------------------------------

resource "aws_apigatewayv2_api" "api_gateway" {
  name          = "ai-agent-api-${local.environment}"
  protocol_type = "HTTP"
  
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["content-type"]
  }
  
  tags = local.tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api_gateway.id
  name        = "$default"
  auto_deploy = true
  
  tags = local.tags
}

# The integration will be created after the Kubernetes service is deployed
# We'll provide instructions for this in the deployment guide

#---------------------------------------------------------------
# Outputs
#---------------------------------------------------------------

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.app_repository.repository_url
}

output "api_gateway_endpoint" {
  description = "API Gateway endpoint URL"
  value       = aws_apigatewayv2_api.api_gateway.api_endpoint
}

output "kubeconfig_command" {
  description = "Command to update kubeconfig for the created EKS cluster"
  value       = "aws eks update-kubeconfig --region us-east-1 --name ${module.eks.cluster_name}"
}