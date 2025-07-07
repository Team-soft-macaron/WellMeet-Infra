provider "aws" {
  region = "ap-northeast-2"
}

# data "archive_file" "run_aws_batch_zip" {
#   type        = "zip"
#   source_file = "./lambda_functions/run_aws_batch/run_aws_batch.py"
#   output_path = "run_aws_batch.zip"
# }

# data "archive_file" "save_restaurants_zip" {
#   type        = "zip"
#   source_dir  = "./lambda_functions/s3_to_DB/save_restaurants.py"
#   output_path = "save_restaurants.zip"
# }

# data "archive_file" "save_reviews_zip" {
#   type        = "zip"
#   source_file = "./lambda_functions/s3_to_DB/save_reviews.py"
#   output_path = "save_reviews.zip"
# }

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.submit_batch_job.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::naver-map-restaurant"
}

# AWS batch를 식당마다 실행하기 위한 Lambda
resource "aws_iam_role" "lambda_batch_role" {
  name = "lambda-batch-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_batch_policy" {
  name = "lambda-batch-policy"
  role = aws_iam_role.lambda_batch_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
        Resource = [
          module.s3_restaurant.bucket_arn,
          "${module.s3_restaurant.bucket_arn}/*"
        ]
      },
      {
        Effect   = "Allow",
        Action   = ["batch:SubmitJob"],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_batch_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_batch_job_queue" "review_crawler" {
  name     = "review-crawler-batch-job"
  state    = "ENABLED"
  priority = 1
  compute_environment_order {
    order               = 1
    compute_environment = module.batch.compute_environment_arn
  }
}

resource "aws_s3_object" "submit_batch_job_lambda_function" {
  bucket = module.s3_lambda_functions.bucket_name
  key    = "submit-batch-job/lambda_function.zip"
}

resource "aws_s3_object" "save_reviews_lambda_function" {
  bucket = module.s3_lambda_functions.bucket_name
  key    = "save-reviews/lambda_function.zip"
}

# Lambda 함수
# resource "aws_lambda_function" "submit_batch_job" {
#   filename         = data.archive_file.run_aws_batch_zip.output_path
#   function_name    = "submit-batch-job-function"
#   role             = aws_iam_role.lambda_batch_role.arn
#   handler          = "run_aws_batch.handler"
#   source_code_hash = data.archive_file.run_aws_batch_zip.output_base64sha256
#   runtime          = "python3.9"
#   timeout          = 900

#   environment {
#     variables = {
#       BATCH_JOB_QUEUE      = aws_batch_job_queue.review_crawler.name
#       BATCH_JOB_DEFINITION = module.batch.job_definition_arn
#     }
#   }
# }

resource "aws_lambda_function" "submit_batch_job" {
  function_name    = "submit-batch-job-function"
  role             = aws_iam_role.lambda_batch_role.arn
  handler          = "lambda_function.handler"
  source_code_hash = aws_s3_object.submit_batch_job_lambda_function.etag
  runtime          = "python3.9"
  timeout          = 900

  s3_bucket = module.s3_lambda_functions.bucket_name
  s3_key    = "submit-batch-job/lambda_function.zip"

  environment {
    variables = {
      BATCH_JOB_QUEUE      = aws_batch_job_queue.review_crawler.name
      BATCH_JOB_DEFINITION = module.batch.job_definition_arn
    }
  }
}

resource "aws_lambda_function" "save_reviews" {
  function_name    = "save-reviews-function"
  role             = aws_iam_role.lambda_batch_role.arn
  handler          = "lambda_function.handler"
  source_code_hash = aws_s3_object.save_reviews_lambda_function.etag
  runtime          = "python3.9"
  timeout          = 900

  s3_bucket = module.s3_lambda_functions.bucket_name
  s3_key    = "save-reviews/lambda_function.zip"
}

# resource "aws_lambda_function" "save_restaurants" {
#   filename         = data.archive_file.save_restaurants_zip.output_path
#   function_name    = "save-restaurants-function"
#   role             = aws_iam_role.lambda_batch_role.arn
#   handler          = "save_restaurants.handler"
#   source_code_hash = data.archive_file.run_aws_batch_zip.output_base64sha256
#   runtime          = "python3.9"
#   timeout          = 900
# }
# resource "aws_lambda_function" "save_reviews" {
#   filename         = data.archive_file.save_reviews_zip.output_path
#   function_name    = "save-reviews-function"
#   role             = aws_iam_role.lambda_batch_role.arn
#   handler          = "save_reviews.handler"
#   source_code_hash = data.archive_file.save_reviews_zip.output_base64sha256
#   runtime          = "python3.9"
#   timeout          = 900
# }

module "s3_restaurant" {
  source               = "./modules/s3"
  bucket_name          = "naver-map-restaurant"
  enable_notification  = true
  lambda_function_arn  = aws_lambda_function.submit_batch_job.arn
  lambda_permission_id = aws_lambda_permission.allow_s3.id
}

module "s3_review" {
  source      = "./modules/s3"
  bucket_name = "naver-map-review"
}

module "s3_atmosphere" {
  source      = "./modules/s3"
  bucket_name = "naver-map-review-atmosphere"
}

# lambda_functions 저장
module "s3_lambda_functions" {
  source      = "./modules/s3"
  bucket_name = "wellmeet-lambda-functions"
}

module "cloudwatch" {
  source               = "./modules/cloudwatch"
  lambda_function_name = aws_lambda_function.submit_batch_job.function_name
}

module "ecr_restaurant" {
  source          = "./modules/ecr"
  repository_name = "restaurant-crawler"
}

module "ecr_review" {
  source          = "./modules/ecr"
  repository_name = "review-crawler"
}

module "ecr_atmosphere" {
  source          = "./modules/ecr"
  repository_name = "atmosphere-classifier"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = "batch-vpc"
  cidr   = "10.0.0.0/16"

  azs            = ["ap-northeast-2a", "ap-northeast-2c"]
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = false
  enable_vpn_gateway = false
}
resource "aws_security_group" "batch_fargate" {
  name        = "batch-fargate-sg"
  description = "Security group for AWS Batch Fargate jobs"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

module "batch" {
  source             = "./modules/batch"
  ecr_repository_url = module.ecr_review.repository_url
  subnet_ids         = module.vpc.public_subnets
  security_group_ids = [aws_security_group.batch_fargate.id]
  aws_region         = var.aws_region_env
  s3_bucket_name     = module.s3_review.bucket_name
}
