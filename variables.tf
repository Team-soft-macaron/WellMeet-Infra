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

variable "openai_api_key" {
  description = "OpenAI API key for Lambda environment variable"
  type        = string
  sensitive   = true
}

variable "wellmeet_db_password" {
  description = "Wellmeet DB password for Lambda environment variable"
  type        = string
  sensitive   = true
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


# variable "api_url" {
#   description = "API URL for Lambda environment variable"
#   type        = string
# }
