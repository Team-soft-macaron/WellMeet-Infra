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
