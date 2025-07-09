# PostgreSQL 전용 보안 그룹 생성
resource "aws_security_group" "postgres" {
  name        = "${var.instance_name}-postgres-sg"
  description = "Security group for PostgreSQL EC2 instance"
  vpc_id      = var.vpc_id
  # PostgreSQL 포트 (5432)를 허용된 보안 그룹에서만 접근 가능
  dynamic "ingress" {
    for_each = var.allowed_security_group_ids
    content {
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = var.allowed_security_group_ids
      description     = "Allowed access"
    }
  }

  # SSH 접근 (관리용 - 필요시 더 제한적으로 설정)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"] # VPC 내부에서만 SSH 허용
    description = "SSH access from VPC"
  }

  # 아웃바운드 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.instance_name}-postgres-sg"
  }
}
# 새로운 private key 생성
resource "tls_private_key" "postgres" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# AWS key pair 생성
resource "aws_key_pair" "postgres" {
  key_name   = "${var.instance_name}-postgres-key"
  public_key = tls_private_key.postgres.public_key_openssh

  tags = {
    Name = "${var.instance_name}-postgres-key"
  }
}

# 생성된 private key를 파일로 저장
resource "local_file" "postgres_private_key" {
  content         = tls_private_key.postgres.private_key_pem
  filename        = "${var.instance_name}-postgres-key.pem"
  file_permission = "0600"
}

# EC2 인스턴스 생성
resource "aws_instance" "postgres" {
  ami                         = var.ami_id
  instance_type               = "t3.medium"
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.postgres.id]
  associate_public_ip_address = false
  key_name                    = aws_key_pair.postgres.key_name

  tags = {
    Name = "${var.instance_name}-postgres"
    Type = "PostgreSQL"
  }
}
