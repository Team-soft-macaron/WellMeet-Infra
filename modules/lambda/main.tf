// 리뷰 크롤링 

// 리뷰 분위기 추출
variable "atmosphere_function_name" {
  description = "Name of the review classifier Lambda function"
  type        = string
  default     = "review-classifier"
}

variable "atmosphere_role_arn" {
  description = "ARN of the Lambda execution role for review classifier"
  type        = string
}

variable "atmosphere_image_uri" {
  description = "ECR image URI for review classifier Lambda"
  type        = string
}

variable "atmosphere_bucket_id" {
  description = "ID of the review S3 bucket"
  type        = string
}

// 식당
variable "restaurant_bucket_id" {
  description = "ID of the restaurant S3 bucket"
  type        = string
}

// 리뷰
variable "review_bucket_id" {
  description = "ID of the review S3 bucket"
  type        = string
}

variable "s3_review_bucket_name" {
  description = "Review S3 bucket name for environment variable"
  type        = string
}

variable "aws_access_key_id" {
  description = "AWS access key ID for Lambda environment"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS secret access key for Lambda environment"
  type        = string
  sensitive   = true
}

variable "aws_region_env" {
  description = "AWS region for Lambda environment variable"
  type        = string
}

variable "place_id" {
  description = "Place ID for Lambda environment variable"
  type        = string
}


# variable "atmosphere_bucket_arn" {
#   description = "ARN of the atmosphere S3 bucket (for Lambda permission)"
#   type        = string
# }

variable "review_bucket_arn" {
  description = "ARN of the review S3 bucket (for Lambda permission)"
  type        = string
}

variable "output_bucket_name" {
  description = "Name of the S3 bucket to upload classified reviews (e.g., naver-map-review-atmosphere)"
  type        = string
}

resource "aws_lambda_function" "atmosphere" {
  function_name = var.atmosphere_function_name
  role          = var.atmosphere_role_arn
  package_type  = "Image"
  image_uri     = var.atmosphere_image_uri
  timeout       = 900
  memory_size   = 3008
  environment {
    variables = {
      REVIEW_BUCKET = var.review_bucket_id
      OUTPUT_BUCKET = var.output_bucket_name
    }
  }
  ephemeral_storage {
    size = 10240
  }
}

resource "aws_lambda_permission" "allow_review_s3" {
  statement_id  = "AllowExecutionFromReviewS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.atmosphere.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.review_bucket_arn
}

output "atmosphere_function_name" {
  value = aws_lambda_function.atmosphere.function_name
}

output "atmosphere_function_arn" {
  value = aws_lambda_function.atmosphere.arn
}

output "atmosphere_permission_id" {
  value = aws_lambda_permission.allow_review_s3.id
}
