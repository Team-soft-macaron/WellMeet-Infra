# Outputs
output "bucket_id" {
  value = aws_s3_bucket.this.id
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}

output "bucket_name" {
  value = aws_s3_bucket.this.bucket
}

output "notification_id" {
  value = var.enable_notification ? aws_s3_bucket_notification.lambda[0].id : null
}
