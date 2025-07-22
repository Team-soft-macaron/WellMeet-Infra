output "endpoint" {
  description = "RDS 인스턴스 엔드포인트"
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "RDS 인스턴스 주소"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "RDS 인스턴스 포트"
  value       = aws_db_instance.this.port
}

output "id" {
  description = "RDS 인스턴스 ID"
  value       = aws_db_instance.this.id
}

output "arn" {
  description = "RDS 인스턴스 ARN"
  value       = aws_db_instance.this.arn
}
