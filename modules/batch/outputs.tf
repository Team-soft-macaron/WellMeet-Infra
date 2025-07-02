
# Outputs
output "compute_environment_arn" {
  description = "ARN of the compute environment"
  value       = aws_batch_compute_environment.fargate_spot.arn
}

output "job_queue_arn" {
  description = "ARN of the job queue"
  value       = aws_batch_job_queue.main.arn
}

output "job_definition_arn" {
  description = "ARN of the job definition"
  value       = aws_batch_job_definition.main.arn
}
