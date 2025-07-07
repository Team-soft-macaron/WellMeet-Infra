output "endpoint" {
  description = "RDS endpoint (host:port)"
  value       = aws_db_instance.postgres.endpoint
}

output "host" {
  description = "RDS hostname only"
  value       = aws_db_instance.postgres.address
}

output "port" {
  description = "Database port"
  value       = aws_db_instance.postgres.port
}

output "database_name" {
  description = "Database name"
  value       = var.db_name
}

output "username" {
  description = "Master username"
  value       = var.username
  sensitive   = true
}

output "jdbc_url" {
  description = "JDBC connection string"
  value       = "jdbc:postgresql://${aws_db_instance.postgres.endpoint}/${var.db_name}"
}

output "connection_string" {
  description = "Full PostgreSQL connection string"
  value       = "postgresql://${var.username}:${var.password}@${aws_db_instance.postgres.endpoint}/${var.db_name}"
  sensitive   = true
}
