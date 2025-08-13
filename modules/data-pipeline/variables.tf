variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "S3_bucket_name" {
  type    = string
  default = "wellmeet-pipeline"
}

variable "restaurant_bucket_directory" {
  type    = string
  default = "restaurant"
}

variable "review_bucket_directory" {
  type    = string
  default = "review"
}

variable "openai_api_key" {
  type = string
}

variable "restaurant_db_host" {
  description = "Restaurant database host"
  type        = string
}

variable "restaurant_db_user" {
  description = "Restaurant database user"
  type        = string
}

variable "restaurant_db_password" {
  description = "Restaurant database password"
  type        = string
  sensitive   = true
}

variable "restaurant_db_name" {
  description = "Restaurant database name"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for Lambda VPC configuration"
  type        = list(string)
}

variable "api_server_security_group_id" {
  description = "Security group ID of the API server (RDS access)"
  type        = string
}
