variable "lambda_role_name" {
  description = "Name of the Lambda execution role"
  type        = string
}

variable "s3_read_arns" {
  description = "List of S3 bucket ARNs for read access"
  type        = list(string)
  default     = []
}

variable "s3_write_arns" {
  description = "List of S3 bucket ARNs for write access"
  type        = list(string)
  default     = []
}
