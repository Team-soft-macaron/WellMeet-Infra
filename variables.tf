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

# variable "api_url" {
#   description = "API URL for Lambda environment variable"
#   type        = string
# }
