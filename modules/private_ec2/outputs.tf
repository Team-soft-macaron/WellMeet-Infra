# 출력 변수
output "instance_id" {
  description = "EC2 인스턴스 ID"
  value       = aws_instance.server.id
}

