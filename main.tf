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

module "recommendation_alb" {
  source          = "./modules/alb"
  name            = "recommendation-alb"
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
  }
  target_attachments = {
    recommendation_api_server = {
      target_group_key = "recommendation_api_server"
      target_id        = module.recommendation_api_server.instance_id
      port             = 8080
    }
  }
  listeners = {
    http = {
      port             = 80
      protocol         = "HTTP"
      target_group_key = "recommendation_api_server"
    }
  }
}



# module "step_function" {
#   source                     = "./modules/step-function"
#   public_subnet_ids          = module.vpc.public_subnets
#   vpc_id                     = module.vpc.vpc_id
#   openai_api_key             = var.openai_api_key
#   restaurant_db_host         = module.rds.address
#   restaurant_db_user         = module.rds.username
#   restaurant_db_password     = module.rds.password
#   restaurant_db_name         = module.rds.db_name
#   private_subnets_for_lambda = [aws_subnet.private_subnet_for_api_server.id]
#   recommend_db_host          = module.rds_postgres.address
#   recommend_db_user          = module.rds_postgres.username
#   recommend_db_password      = module.rds_postgres.password
#   recommend_db_name          = module.rds_postgres.db_name
#   recommend_db_port          = module.rds_postgres.port
#   # security_groups_for_lambda = [aws_security_group.lambda_sg.id]
#   # access_rds_role_arn        = aws_iam_role.access_rds_role.arn
# }

module "data_pipeline" {
  source                      = "./modules/data-pipeline"
  vpc_id                      = module.vpc.vpc_id
  public_subnet_ids           = module.vpc.public_subnets
  S3_bucket_name              = "wellmeet-pipeline"
  restaurant_bucket_directory = "restaurant"
  review_bucket_directory     = "review"

}

# wellmeet API 서버
module "wellmeet_api_server_user" {
  source             = "./modules/private-ec2"
  subnet_id          = aws_subnet.private_subnet_for_api_server.id
  vpc_id             = module.vpc.vpc_id
  instance_name      = "wellmeet-api-server-user"
  security_group_ids = [aws_security_group.api_server.id]
}

# wellmeet API 서버
module "wellmeet_api_server_owner" {
  source             = "./modules/private-ec2"
  subnet_id          = aws_subnet.private_subnet_for_api_server.id
  vpc_id             = module.vpc.vpc_id
  instance_name      = "wellmeet-api-server-owner"
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

module "rds" {
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

module "wellmeet_user_alb" {
  source          = "./modules/alb"
  name            = "wellmeet-user-alb"
  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.public_subnets
  security_groups = [aws_security_group.application_load_balancer.id]
  target_groups = {
    wellmeet_api_server_user = {
      name              = "wellmeet-api-server-user"
      port              = 8080
      protocol          = "HTTP"
      health_check_path = "/health"
    }
  }
  target_attachments = {
    wellmeet_api_server_user = {
      target_group_key = "wellmeet_api_server_user"
      target_id        = module.wellmeet_api_server_user.instance_id
      port             = 8080
    }
  }
  listeners = {
    http = {
      port             = 80
      protocol         = "HTTP"
      target_group_key = "wellmeet_api_server_user"
    }
  }
}

module "wellmeet_owner_alb" {
  source          = "./modules/alb"
  name            = "wellmeet-owner-alb"
  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.public_subnets
  security_groups = [aws_security_group.application_load_balancer.id]
  target_groups = {
    wellmeet_api_server_owner = {
      name              = "wellmeet-api-server-owner"
      port              = 8080
      protocol          = "HTTP"
      health_check_path = "/health"
    }
  }
  target_attachments = {
    wellmeet_api_server_owner = {
      target_group_key = "wellmeet_api_server_owner"
      target_id        = module.wellmeet_api_server_owner.instance_id
      port             = 8080
    }
  }
  listeners = {
    http = {
      port             = 80
      protocol         = "HTTP"
      target_group_key = "wellmeet_api_server_owner"
    }
  }
}

# SQS
