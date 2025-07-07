variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Storage in GB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "restaurant_db"
}

variable "username" {
  description = "Master username"
  type        = string
  default     = "postgres"
}

variable "password" {
  description = "Master password"
  type        = string
  sensitive   = true
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for RDS"
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "Security group allowed to connect"
  type        = string
}
