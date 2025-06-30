variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "r6i.large"
}

variable "ami_id" {
  description = "AMI ID for Ubuntu latest"
  type        = string
}
