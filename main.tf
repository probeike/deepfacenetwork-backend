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

# Check if the bucket already exists
data "aws_s3_bucket" "existing_bucket" {
  bucket = "starter-bucket-${var.aws_account_id}-${local.environment}"
  # This will fail if the bucket doesn't exist, but that's handled by the count parameter in the resource
}

# Create the bucket only if it doesn't exist
resource "aws_s3_bucket" "starter-bucket" {
  # Skip creation if the bucket already exists
  count  = try(data.aws_s3_bucket.existing_bucket.bucket, "") != "" ? 0 : 1
  
  bucket = "starter-bucket-${var.aws_account_id}-${local.environment}"
  tags   = local.tags
}

# Local to store the bucket name regardless of whether it was created or already existed
locals {
  bucket_name = try(data.aws_s3_bucket.existing_bucket.bucket, aws_s3_bucket.starter-bucket[0].bucket)
}

#---------------------------------------------------------------
# Outputs
#---------------------------------------------------------------

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = local.bucket_name
}