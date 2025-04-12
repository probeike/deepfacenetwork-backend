variable "aws_account_id" {
  type        = string
  description = "The AWS account ID used to make resources globally unique"
}

# We'll use Terraform workspaces instead of this variable
# The workspace name will automatically be "default" (for dev) or "prod"
locals {
  environment = terraform.workspace == "default" ? "dev" : terraform.workspace
  
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
# Outputs
#---------------------------------------------------------------

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.starter-bucket.bucket
}