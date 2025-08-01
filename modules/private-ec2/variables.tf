# 변수 정의
variable "subnet_id" {
  description = "Public 서브넷 ID"
  type        = string
}

variable "instance_name" {
  description = "EC2 인스턴스 이름"
  type        = string
  default     = "public-ec2"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs"
  type        = list(string)
}
