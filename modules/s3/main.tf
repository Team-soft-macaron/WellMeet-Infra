# Variables
variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "enable_notification" {
  description = "Whether to enable S3 -> Lambda notification (for atmosphere bucket)"
  type        = bool
  default     = false
}

variable "lambda_function_arn" {
  description = "ARN of the Lambda function triggered by S3 notification"
  type        = string
  default     = null
}

variable "lambda_permission_id" {
  description = "ID of the Lambda permission resource for S3 trigger"
  type        = any
  default     = null
}

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_notification" "lambda" {
  count  = var.enable_notification ? 1 : 0
  bucket = aws_s3_bucket.this.id

  lambda_function {
    lambda_function_arn = var.lambda_function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".json"
  }

  depends_on = [var.lambda_permission_id]
}

# Outputs
output "bucket_id" {
  value = aws_s3_bucket.this.id
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}

output "notification_id" {
  value = var.enable_notification ? aws_s3_bucket_notification.lambda[0].id : null
}
