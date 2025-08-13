provider "aws" {
  region = "ap-northeast-2"
}

# VPC
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = "wellmeet"
  cidr   = "10.0.0.0/16"

  azs             = ["ap-northeast-2a", "ap-northeast-2c"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
  private_subnets = ["10.0.1.0/24", "10.0.3.0/24"]

  enable_nat_gateway = false
  enable_vpn_gateway = false

  enable_dns_hostnames = true # 반드시 true
  enable_dns_support   = true # 반드시 true
}

# private API 서버 라우트 테이블
resource "aws_route_table" "private_ec2_route_table" {
  vpc_id = module.vpc.vpc_id

  tags = {
    Name = "private-ec2-route-table"
  }
}

resource "aws_route" "private_ec2_to_nat_instance" {
  route_table_id         = aws_route_table.private_ec2_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.ec2.nat_instance_eni_id
}

resource "aws_route_table_association" "private_ec2_route_table_association" {
  subnet_id      = aws_subnet.private_subnet_for_api_server.id
  route_table_id = aws_route_table.private_ec2_route_table.id
}

# API 서버 private subnet
resource "aws_subnet" "private_subnet_for_api_server" {
  vpc_id            = module.vpc.vpc_id
  cidr_block        = "10.0.2.0/24"
  availability_zone = module.vpc.azs[0]

  tags = {
    Name = "private-subnet-for-api-server"
  }
}

# API 서버 보안 그룹
resource "aws_security_group" "api_server" {
  name        = "api-server-sg"
  description = "Security group for API Server"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
    description     = "Allow SSH traffic"
    security_groups = [module.ec2.security_group_id] # bastion host 접근 허용
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ALB 보안 그룹
resource "aws_security_group" "application_load_balancer" {
  name        = "application-load-balancer-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# NAT instance + bastion host
module "ec2" {
  source        = "./modules/ec2"
  subnet_id     = module.vpc.public_subnets[0]
  vpc_id        = module.vpc.vpc_id
  instance_name = "ec2"
}

# 추천 API 서버
module "recommendation_api_server" {
  source             = "./modules/private-ec2"
  subnet_id          = aws_subnet.private_subnet_for_api_server.id
  vpc_id             = module.vpc.vpc_id
  instance_name      = "recommendation-api-server"
  security_group_ids = [aws_security_group.api_server.id]
}

# 통합 ALB
module "external_alb" {
  source          = "./modules/alb"
  name            = "wellmeet-external-alb"
  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.public_subnets
  security_groups = [aws_security_group.application_load_balancer.id]
  target_groups = {
    recommendation_api_server = {
      name              = "recommendation-api-server"
      port              = 8080
      protocol          = "HTTP"
      health_check_path = "/health"
    }
    wellmeet_api_server_user = {
      name              = "wellmeet-api-server-user"
      port              = 8080
      protocol          = "HTTP"
      health_check_path = "/health"
    }
    wellmeet_api_server_owner = {
      name              = "wellmeet-api-server-owner"
      port              = 8080
      protocol          = "HTTP"
      health_check_path = "/health"
    }
    notification_api_server = {
      name              = "notification-api-server"
      port              = 8080
      protocol          = "HTTP"
      health_check_path = "/health"
    }
  }
  target_attachments = {
    recommendation_api_server = {
      target_group_key = "recommendation_api_server"
      target_id        = module.recommendation_api_server.instance_id
      port             = 8080
    }
    wellmeet_api_server_user = {
      target_group_key = "wellmeet_api_server_user"
      target_id        = module.wellmeet_api_server_user.instance_id
      port             = 8080
    }
    wellmeet_api_server_owner = {
      target_group_key = "wellmeet_api_server_owner"
      target_id        = module.wellmeet_api_server_owner.instance_id
      port             = 8080
    }
    notification_api_server = {
      target_group_key = "notification_api_server"
      target_id        = module.notification_server.instance_id
      port             = 8080
    }
  }
  listeners = {
    http = {
      port                     = 80
      protocol                 = "HTTP"
      default_target_group_key = "wellmeet_api_server_user" # 기본값으로 user API로 라우팅
      rules = {
        recommendation = {
          priority         = 100
          path_patterns    = ["/recommendation/*"]
          target_group_key = "recommendation_api_server"
        }
        user_api = {
          priority         = 200
          path_patterns    = ["/user/*"]
          target_group_key = "wellmeet_api_server_user"
        }
        owner_api = {
          priority         = 300
          path_patterns    = ["/owner/*"]
          target_group_key = "wellmeet_api_server_owner"
        }
        notification_api = {
          priority         = 400
          path_patterns    = ["/notification/*"]
          target_group_key = "notification_api_server"
        }
      }
    }
  }
}

module "data_pipeline" {
  source                       = "./modules/data-pipeline"
  vpc_id                       = module.vpc.vpc_id
  public_subnet_ids            = module.vpc.public_subnets
  S3_bucket_name               = "wellmeet-pipeline"
  restaurant_bucket_directory  = "restaurant"
  review_bucket_directory      = "review"
  openai_api_key               = var.openai_api_key
  restaurant_db_host           = var.restaurant_db_host
  restaurant_db_user           = var.restaurant_db_user
  restaurant_db_password       = var.restaurant_db_password
  restaurant_db_name           = var.restaurant_db_name
  private_subnet_ids           = [aws_subnet.private_subnet_for_api_server.id]
  api_server_security_group_id = aws_security_group.api_server.id
}

# wellmeet API user 서버
module "wellmeet_api_server_user" {
  source             = "./modules/private-ec2"
  subnet_id          = aws_subnet.private_subnet_for_api_server.id
  vpc_id             = module.vpc.vpc_id
  instance_name      = "wellmeet-api-server-user"
  security_group_ids = [aws_security_group.api_server.id]
}

# wellmeet API owner 서버
module "wellmeet_api_server_owner" {
  source             = "./modules/private-ec2"
  subnet_id          = aws_subnet.private_subnet_for_api_server.id
  vpc_id             = module.vpc.vpc_id
  instance_name      = "wellmeet-api-server-owner"
  security_group_ids = [aws_security_group.api_server.id]
}

# notification 서버
module "notification_server" {
  source             = "./modules/private-ec2"
  subnet_id          = aws_subnet.private_subnet_for_api_server.id
  vpc_id             = module.vpc.vpc_id
  instance_name      = "notification-server"
  security_group_ids = [aws_security_group.api_server.id]
}

# RDS 보안 그룹
resource "aws_security_group" "rds" {
  name        = "wellmeet-rds-sg"
  description = "Security group for RDS MySQL"
  vpc_id      = module.vpc.vpc_id

  # API 서버, bastion host, lambda로부터의 MySQL 접근 허용
  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    # security_groups = [aws_security_group.api_server.id, module.step_function.save_restaurant_to_db_lambda_sg, module.ec2.security_group_id]
    security_groups = [aws_security_group.api_server.id, module.ec2.security_group_id]
    description     = "Allow MySQL access from API servers"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "wellmeet-rds-sg"
  }
}

module "wellmeet_db" {
  source                 = "./modules/rds"
  identifier             = "wellmeet-db"
  subnet_ids             = module.vpc.private_subnets
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_name                = "wellmeet"
  username               = "wellmeet"
  password               = var.wellmeet_db_password
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
}

module "notification_db" {
  source                 = "./modules/rds"
  identifier             = "wellmeet-notification-db"
  subnet_ids             = module.vpc.private_subnets
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_name                = "notification"
  username               = "wellmeet"
  password               = var.wellmeet_db_password
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
}

module "rds_postgres" {
  source                 = "./modules/rds-postgres"
  identifier             = "recommendation-db"
  subnet_ids             = module.vpc.private_subnets
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_name                = "recommendation"
  username               = "wellmeet"
  password               = var.wellmeet_db_password
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
}

# SQS
