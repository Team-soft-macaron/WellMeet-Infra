# 새로운 private key 생성
resource "tls_private_key" "ec2" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# AWS key pair 생성
resource "aws_key_pair" "ec2" {
  key_name   = "${var.instance_name}-key"
  public_key = tls_private_key.ec2.public_key_openssh

  tags = {
    Name = "${var.instance_name}-key"
  }
}

# 생성된 private key를 파일로 저장
resource "local_file" "ec2_private_key" {
  content         = tls_private_key.ec2.private_key_pem
  filename        = "${var.instance_name}-key.pem"
  file_permission = "0600"
}

# EC2 인스턴스 생성
resource "aws_instance" "server" {
  ami           = "ami-0662f4965dfc70aca" # 고정 AMI ID
  instance_type = "t3.micro"

  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids
  associate_public_ip_address = false
  key_name                    = aws_key_pair.ec2.key_name

  # 루트 볼륨 설정
  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  # 간단한 초기화 스크립트
  user_data = <<-EOF
    #!/bin/bash
    apt-get update
  EOF

  tags = {
    Name = var.instance_name
    Type = "Public"
  }
}
