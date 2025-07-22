# Variables
variable "review_crawler_ecr_repository_url" {
  description = "ECR repository URL for the container image"
  type        = string
  default     = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/my-app:latest"
}

variable "restaurant_crawler_ecr_repository_url" {
  description = "ECR repository URL for the container image"
  type        = string
  default     = "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/my-app:latest"
}

variable "subnet_ids" {
  description = "List of subnet IDs for the compute environment"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for the compute environment"
  type        = list(string)
}

variable "aws_region" {
  description = "AWS region for the compute environment"
  type        = string
}

variable "S3_bucket_name" {
  description = "S3 bucket name for upload"
  type        = string
}

variable "restaurant_bucket_directory" {
  description = "S3 bucket name for restaurant"
  type        = string
}

variable "review_bucket_directory" {
  description = "S3 bucket name for review"
  type        = string
}
