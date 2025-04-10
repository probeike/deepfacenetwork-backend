variable "aws_account_id" {
  type = string
  description = "The AWS account ID used to make resources globally unique"
}

resource "aws_s3_bucket" "starter-bucket" {
  bucket = "starter-bucket-${var.aws_account_id}"
}