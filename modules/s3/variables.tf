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
