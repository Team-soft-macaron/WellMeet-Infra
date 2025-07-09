output "postgres_instance_id" {
  description = "EC2 인스턴스 ID"
  value       = aws_instance.postgres.id
}

output "postgres_security_group_id" {
  description = "PostgreSQL 보안 그룹 ID"
  value       = aws_security_group.postgres.id
}
