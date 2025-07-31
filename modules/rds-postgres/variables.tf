
variable "identifier" {
  description = "RDS 인스턴스 식별자"
  type        = string
}

variable "subnet_ids" {
  description = "RDS를 배치할 서브넷 ID 리스트 (최소 2개의 다른 AZ)"
  type        = list(string)
}

variable "vpc_security_group_ids" {
  description = "RDS에 연결할 보안 그룹 ID 리스트"
  type        = list(string)
}

variable "db_name" {
  description = "초기 데이터베이스 이름"
  type        = string
}

variable "username" {
  description = "마스터 사용자 이름"
  type        = string
  default     = "admin"
}

variable "password" {
  description = "마스터 사용자 비밀번호 (최소 8자)"
  type        = string
  sensitive   = true
}

variable "instance_class" {
  description = "RDS 인스턴스 클래스"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "할당된 스토리지 크기 (GB)"
  type        = number
  default     = 20
}
