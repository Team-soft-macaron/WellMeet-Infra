output "batch_fargate_security_group_id" {
  description = "Security group ID for batch fargate jobs"
  value       = aws_security_group.batch_fargate.id
}

output "data_pipeline_role_arn" {
  description = "ARN of the data pipeline IAM role"
  value       = aws_iam_role.data_pipeline_role.arn
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for data pipeline"
  value       = module.s3_data_pipeline.bucket_arn
}

output "restaurant_ecr_repository_url" {
  description = "URL of the restaurant crawler ECR repository"
  value       = module.ecr_restaurant.repository_url
}

output "review_ecr_repository_url" {
  description = "URL of the review crawler ECR repository"
  value       = module.ecr_review.repository_url
}

output "embedding_queue_url" {
  description = "URL of the SQS queue for embedding processing"
  value       = aws_sqs_queue.embedding_queue.url
}

output "embedding_queue_arn" {
  description = "ARN of the SQS queue for embedding processing"
  value       = aws_sqs_queue.embedding_queue.arn
}

output "create_embedding_lambda_arn" {
  description = "ARN of the create-embedding Lambda function"
  value       = aws_lambda_function.create_embedding.arn
}
