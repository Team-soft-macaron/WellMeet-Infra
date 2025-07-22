resource "aws_db_subnet_group" "this" {
  name       = "${var.identifier}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.identifier}-subnet-group"
  }
}

# RDS 인스턴스 생성
resource "aws_db_instance" "this" {
  identifier = var.identifier

  # 엔진 설정
  engine         = "mysql"
  engine_version = "8.0.35"

  # 인스턴스 설정
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  # 데이터베이스 설정
  db_name  = var.db_name
  username = var.username
  password = var.password
  port     = 3306

  # 네트워크 설정
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.vpc_security_group_ids
  publicly_accessible    = false

  # 백업 설정
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # 고가용성 설정
  multi_az = false

  # 모니터링 설정
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  # 기타 설정
  deletion_protection = false
  skip_final_snapshot = true
  apply_immediately   = true

  tags = {
    Name = var.identifier
  }
}
