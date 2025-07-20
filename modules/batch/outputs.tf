
# Outputs
output "compute_environment_arn" {
  description = "ARN of the compute environment"
  value       = aws_batch_compute_environment.fargate_spot.arn
}

output "review_job_queue_arn" {
  description = "ARN of the review job queue"
  value       = aws_batch_job_queue.review_crawler.arn
}
output "restaurant_job_queue_arn" {
  description = "ARN of the restaurant job queue"
  value       = aws_batch_job_queue.restaurant_crawler.arn
}

output "review_job_definition_arn" {
  description = "ARN of the review job definition"
  value       = aws_batch_job_definition.review_crawler.arn
}
output "restaurant_job_definition_arn" {
  description = "ARN of the restaurant job definition"
  value       = aws_batch_job_definition.restaurant_crawler.arn
}
