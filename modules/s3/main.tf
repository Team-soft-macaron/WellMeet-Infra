# Variables
variable "restaurant_bucket_name" {
  description = "Name of the restaurant S3 bucket"
  type        = string
}

variable "review_bucket_name" {
  description = "Name of the review S3 bucket"
  type        = string
}

variable "atmosphere_bucket_name" {
  description = "Name of the atmosphere S3 bucket"
  type        = string
}

variable "atmosphere_lambda_function_arn" {
  description = "ARN of the Lambda function triggered by review S3 notification"
  type        = string
}

variable "atmosphere_lambda_permission_id" {
  description = "ID of the Lambda permission resource for review S3 trigger"
  type        = any
}

resource "aws_s3_bucket" "restaurant" {
  bucket = var.restaurant_bucket_name
}

resource "aws_s3_bucket" "review" {
  bucket = var.review_bucket_name
}

resource "aws_s3_bucket" "atmosphere" {
  bucket = var.atmosphere_bucket_name
}

resource "aws_s3_bucket_notification" "review_upload" {
  bucket = aws_s3_bucket.review.id

  lambda_function {
    lambda_function_arn = var.atmosphere_lambda_function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".json"
  }

  depends_on = [var.atmosphere_lambda_permission_id]
}

# Outputs
output "restaurant_bucket_id" {
  value = aws_s3_bucket.restaurant.id
}

output "restaurant_bucket_arn" {
  value = aws_s3_bucket.restaurant.arn
}

output "review_bucket_id" {
  value = aws_s3_bucket.review.id
}

output "review_bucket_arn" {
  value = aws_s3_bucket.review.arn
}

output "atmosphere_bucket_id" {
  value = aws_s3_bucket.atmosphere.id
}

output "atmosphere_bucket_arn" {
  value = aws_s3_bucket.atmosphere.arn
}
output "notification_id" {
  value = aws_s3_bucket_notification.review_upload.id
}
