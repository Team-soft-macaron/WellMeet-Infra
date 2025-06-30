# review crawling Lambda 함수에 필요한 variable
variable "s3_review_bucket_name" {
  description = "Review S3 bucket name for Lambda environment variable"
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

# variable "ec2_key_name" {
#   description = "Name of the SSH key pair to use for EC2 instance."
#   type        = string
# }

# variable "ec2_ami_id" {
#   description = "AMI ID for Ubuntu latest to use for EC2 instance."
#   type        = string
# }

# variable "ec2_instance_profile_arn" {
#   description = "IAM instance profile ARN for EC2 (for ECR/ECS access, etc)"
#   type        = string
#   default     = ""
# }

# variable "atmosphere_role_arn" {
#   description = "ARN of the Lambda execution role for review classifier"
#   type        = string
# }

# variable "atmosphere_image_uri" {
#   description = "ECR image URI for review classifier Lambda"
#   type        = string
# }

# variable "atmosphere_output_bucket_name" {
#   description = "Name of the S3 bucket to upload classified reviews (e.g., naver-map-review-atmosphere)"
#   type        = string
# }

# variable "atmosphere_function_name" {
#   description = "Name of the atmosphere Lambda function"
#   type        = string
#   default     = "atmosphere-classifier"
# }
