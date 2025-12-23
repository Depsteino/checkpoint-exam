resource "aws_s3_bucket" "app_bucket" {
  bucket_prefix = "${var.project_name}-data-"
  force_destroy = true
}

# NOTE: Disabled due to SCP explicit deny in exam AWS account.
# resource "aws_s3_bucket_public_access_block" "app_bucket" {
#   bucket                  = aws_s3_bucket.app_bucket.id
#   block_public_acls       = true
#   ignore_public_acls      = true
#   block_public_policy     = true
#   restrict_public_buckets = true
# }

resource "aws_sqs_queue" "app_queue" {
  name = "${var.project_name}-queue"
}

locals {
  repo_names = ["microservice-1-producer", "microservice-2-consumer"]
}

resource "aws_ecr_repository" "repo" {
  count        = length(local.repo_names)
  name         = local.repo_names[count.index]
  force_delete = true
}
