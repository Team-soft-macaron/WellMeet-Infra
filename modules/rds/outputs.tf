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

output "username" {
  description = "RDS 인스턴스 사용자 이름"
  value       = aws_db_instance.this.username
}

output "password" {
  description = "RDS 인스턴스 비밀번호"
  value       = aws_db_instance.this.password
}

output "db_name" {
  description = "RDS 인스턴스 데이터베이스 이름"
  value       = aws_db_instance.this.db_name
}
