variable "name" {
  description = "ALB 이름"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnets" {
  description = "ALB를 배치할 서브넷 ID 목록"
  type        = list(string)
}

variable "security_groups" {
  description = "ALB에 연결할 보안 그룹 ID 목록"
  type        = list(string)
}

variable "target_groups" {
  description = "타겟 그룹 설정"
  type = map(object({
    name              = string
    port              = number
    protocol          = string
    health_check_path = string
  }))
}

variable "listeners" {
  description = "리스너 설정"
  type = map(object({
    port             = number
    protocol         = string
    target_group_key = optional(string) # 규칙이 없을 때 사용
    rules = optional(map(object({
      priority         = number
      path_patterns    = optional(list(string))
      target_group_key = string
    })))
    default_target_group_key = optional(string) # 규칙이 있을 때 기본 타겟 그룹
  }))
}

variable "target_attachments" {
  description = "타겟 그룹에 연결할 인스턴스"
  type = map(object({
    target_group_key = string
    target_id        = string
    port             = number
  }))
  default = {}
}
