variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "restaurant_bucket_directory" {
  type    = string
  default = "restaurant"
}

variable "S3_bucket_name" {
  type    = string
  default = "wellmeet-data-pipeline"
}

variable "review_bucket_directory" {
  type    = string
  default = "review"
}

variable "category_bucket_directory" {
  type    = string
  default = "category"
}

variable "embedding_vector_bucket_directory" {
  type    = string
  default = "embedding_vector"
}

variable "openai_api_key" {
  type = string
}

variable "restaurant_db_host" {
  type = string
}

variable "restaurant_db_user" {
  type = string
}

variable "restaurant_db_password" {
  type = string
}

variable "restaurant_db_name" {
  type = string
}

variable "private_subnets_for_lambda" {
  type = list(string)
}
