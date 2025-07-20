provider "aws" {
  region = "ap-northeast-2"
}

# resource "aws_lambda_permission" "allow_restaurant_s3" {
#   statement_id  = "AllowExecutionFromS3"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.submit_batch_job.function_name
#   principal     = "s3.amazonaws.com"
#   source_arn    = "arn:aws:s3:::naver-map-restaurant"
# }

# resource "aws_lambda_permission" "allow_review_s3" {
#   statement_id  = "AllowExecutionFromS3"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.save_reviews.function_name
#   principal     = "s3.amazonaws.com"
#   source_arn    = "arn:aws:s3:::naver-map-review"
# }

# AWS batch를 식당마다 실행하기 위한 Lambda
# resource "aws_iam_role" "lambda_batch_role" {
#   name = "lambda-batch-role"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Action = "sts:AssumeRole"
#       Effect = "Allow"
#       Principal = {
#         Service = "lambda.amazonaws.com"
#       }
#     }]
#   })
# }

# resource "aws_iam_role_policy" "lambda_batch_policy" {
#   name = "lambda-batch-policy"
#   role = aws_iam_role.lambda_batch_role.id
#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
#         Resource = [
#           module.s3_restaurant.bucket_arn,
#           "${module.s3_restaurant.bucket_arn}/*",
#           module.s3_review.bucket_arn,
#           "${module.s3_review.bucket_arn}/*"
#         ]
#       },
#       {
#         Effect   = "Allow",
#         Action   = ["batch:SubmitJob"],
#         Resource = "*"
#       },
#       {
#         Effect = "Allow",
#         Action = [
#           "logs:CreateLogGroup",
#           "logs:CreateLogStream",
#           "logs:PutLogEvents"
#         ],
#         Resource = "arn:aws:logs:*:*:*"
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "lambda_logs" {
#   role       = aws_iam_role.lambda_batch_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
# }

# resource "aws_batch_job_queue" "review_crawler" {
#   name     = "review-crawler-batch-job"
#   state    = "ENABLED"
#   priority = 1
#   compute_environment_order {
#     order               = 1
#     compute_environment = module.batch.compute_environment_arn
#   }
# }

# resource "aws_s3_object" "submit_batch_job_lambda_function" {
#   bucket = module.s3_lambda_functions.bucket_name
#   key    = "submit-batch-job/lambda_function.zip"
# }

# resource "aws_s3_object" "save_reviews_lambda_function" {
#   bucket = module.s3_lambda_functions.bucket_name
#   key    = "save-reviews/lambda_function.zip"
# }

# resource "aws_lambda_function" "submit_batch_job" {
#   function_name    = "submit-batch-job-function"
#   role             = aws_iam_role.lambda_batch_role.arn
#   handler          = "lambda_function.handler"
#   source_code_hash = aws_s3_object.submit_batch_job_lambda_function.etag

#   runtime = "python3.9"
#   timeout = 900

#   s3_bucket = module.s3_lambda_functions.bucket_name
#   s3_key    = "submit-batch-job/lambda_function.zip"

#   environment {
#     variables = {
#       BATCH_JOB_QUEUE      = aws_batch_job_queue.review_crawler.name
#       BATCH_JOB_DEFINITION = module.batch.job_definition_arn
#       API_URL              = var.api_url
#     }
#   }
# }

# resource "aws_lambda_function" "save_reviews" {
#   function_name    = "save-reviews-function"
#   role             = aws_iam_role.lambda_batch_role.arn
#   handler          = "lambda_function.handler"
#   source_code_hash = aws_s3_object.save_reviews_lambda_function.etag
#   runtime          = "python3.9"
#   timeout          = 900

#   s3_bucket = module.s3_lambda_functions.bucket_name
#   s3_key    = "save-reviews/lambda_function.zip"

#   environment {
#     variables = {
#       API_URL = var.api_url
#     }
#   }
# }

# module "s3_restaurant" {
#   source              = "./modules/s3"
#   bucket_name         = "naver-map-restaurant"
#   enable_notification = false
#   # lambda_function_arn  = aws_lambda_function.submit_batch_job.arn
#   # lambda_permission_id = aws_lambda_permission.allow_restaurant_s3.id
# }

# module "s3_review" {
#   source              = "./modules/s3"
#   bucket_name         = "naver-map-review"
#   enable_notification = false
#   # lambda_function_arn  = aws_lambda_function.save_reviews.arn
#   # lambda_permission_id = aws_lambda_permission.allow_review_s3.id
# }
# lambda_functions 저장
module "s3_lambda_functions" {
  source      = "./modules/s3"
  bucket_name = "wellmeet-lambda-functions"
}

# module "cloudwatch" {
#   source               = "./modules/cloudwatch"
#   lambda_function_name = aws_lambda_function.submit_batch_job.function_name
# }

module "s3_step_functions" {
  source      = "./modules/s3"
  bucket_name = "wellmeet-step-functions"
}

# module "ecr_restaurant" {
#   source          = "./modules/ecr"
#   repository_name = "restaurant-crawler"
# }

# module "ecr_review" {
#   source          = "./modules/ecr"
#   repository_name = "review-crawler"
# }

resource "aws_subnet" "private_subnet_for_recommendation_api_server" {
  vpc_id            = module.vpc.vpc_id
  cidr_block        = "10.0.2.0/24"
  availability_zone = module.vpc.azs[0]

  tags = {
    Name = "private-subnet-for-recommendation-api-server"
  }
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = "batch-vpc"
  cidr   = "10.0.0.0/16"

  azs             = ["ap-northeast-2a", "ap-northeast-2c"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
  private_subnets = ["10.0.1.0/24"]

  enable_nat_gateway = false
  enable_vpn_gateway = false
}
# resource "aws_security_group" "batch_fargate" {
#   name        = "batch-fargate-sg"
#   description = "Security group for AWS Batch Fargate jobs"
#   vpc_id      = module.vpc.vpc_id

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

# }

# private API 서버
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
  subnet_id      = aws_subnet.private_subnet_for_recommendation_api_server.id
  route_table_id = aws_route_table.private_ec2_route_table.id
}

resource "aws_security_group" "recommendation_api_server" {
  name        = "recommendation-api-server-sg"
  description = "Security group for Recommendation API Server"
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



# module "rds" {
#   source                     = "./modules/rds"
#   name                       = "wellmeetdb"
#   instance_class             = "db.t3.micro"
#   allocated_storage          = 20
#   db_name                    = "wellmeetdb"
#   username                   = "postgres"
#   password                   = var.rds_password
#   vpc_id                     = module.vpc.vpc_id
#   subnet_ids                 = module.vpc.private_subnets
#   allowed_security_group_ids = [aws_security_group.batch_fargate.id, aws_security_group.ec2_rds_access.id]
# }
# module "ec2" {
#   source        = "./modules/ec2"
#   instance_type = "t3.micro"
#   ami_id        = "ami-0c9c942bd7bf113a2" # Ubuntu 22.04 LTS in ap-northeast-2
# }

# Security group for EC2 to access RDS
# resource "aws_security_group" "ec2_rds_access" {
#   name        = "ec2-rds-access-sg"
#   description = "Security group for EC2 to access RDS"
#   vpc_id      = module.vpc.vpc_id

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }


module "postgres" {
  source                     = "./modules/postgres"
  subnet_id                  = module.vpc.private_subnets[0]
  allowed_security_group_ids = [module.ec2.security_group_id, aws_security_group.recommendation_api_server.id]
  # db_password                = var.db_password
  # db_name                    = "wellmeet"
  # db_username                = "postgres"
  vpc_id        = module.vpc.vpc_id
  ami_id        = "ami-0aa6e95177252a286"
  instance_name = "recommendation"
}

module "ec2" {
  source        = "./modules/ec2"
  subnet_id     = module.vpc.public_subnets[0]
  vpc_id        = module.vpc.vpc_id
  instance_name = "ec2"
}

module "recommendation_api_server" {
  source             = "./modules/private_ec2"
  subnet_id          = aws_subnet.private_subnet_for_recommendation_api_server.id
  vpc_id             = module.vpc.vpc_id
  instance_name      = "recommendation-api-server"
  security_group_ids = [aws_security_group.recommendation_api_server.id]
}

module "alb" {
  source          = "./modules/alb"
  name            = "application-load-balancer"
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

module "step_function" {
  source            = "./modules/step-function"
  public_subnet_ids = module.vpc.public_subnets
  vpc_id            = module.vpc.vpc_id
  # aws_region          = "ap-northeast-2"
  # api_url             = "http://${module.alb.alb_dns_name}/api/v1/recommendation"
}
