variable "subnet_id" {
  description = "EC2를 배포할 서브넷 ID"
  type        = string
}

variable "allowed_security_group_ids" {
  description = "PostgreSQL 접근을 허용할 보안 그룹 ID 목록"
  type        = list(string)
}

variable "instance_name" {
  description = "EC2 인스턴스 이름"
  type        = string
}

# 고정 AMI ID 사용
variable "ami_id" {
  description = "Ubuntu AMI ID"
  type        = string
  default     = "ami-0662f4965dfc70aca"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}
