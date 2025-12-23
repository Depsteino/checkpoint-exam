output "bucket_id" { value = aws_s3_bucket.app_bucket.id }
output "bucket_arn" { value = aws_s3_bucket.app_bucket.arn }
output "sqs_url" { value = aws_sqs_queue.app_queue.id }
output "sqs_arn" { value = aws_sqs_queue.app_queue.arn }
output "repo_urls" { value = aws_ecr_repository.repo[*].repository_url }
