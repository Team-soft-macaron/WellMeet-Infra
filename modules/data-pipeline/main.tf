# S3 bucket for data pipeline
module "s3_data_pipeline" {
  source      = "../s3"
  bucket_name = var.S3_bucket_name
}

# ECR repositories for crawler images
module "ecr_restaurant" {
  source          = "../ecr"
  repository_name = "restaurant-crawler"
}

module "ecr_review" {
  source          = "../ecr"
  repository_name = "review-crawler"
}

# Security group for batch jobs
resource "aws_security_group" "batch_fargate" {
  name        = "data-pipeline-batch-fargate-sg"
  description = "Security group for AWS Batch Fargate jobs in data pipeline"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# AWS Batch module for crawling jobs
module "batch" {
  source                                = "../batch"
  subnet_ids                            = var.public_subnet_ids
  security_group_ids                    = [aws_security_group.batch_fargate.id]
  aws_region                            = "ap-northeast-2"
  S3_bucket_name                        = var.S3_bucket_name
  restaurant_bucket_directory           = var.restaurant_bucket_directory
  review_bucket_directory               = var.review_bucket_directory
  review_crawler_ecr_repository_url     = module.ecr_review.repository_url
  restaurant_crawler_ecr_repository_url = module.ecr_restaurant.repository_url
}

# IAM Role for data pipeline operations
resource "aws_iam_role" "data_pipeline_role" {
  name = "data-pipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "batch.amazonaws.com"
      }
    }]
  })
}

# IAM Policy for data pipeline operations
resource "aws_iam_role_policy" "data_pipeline_policy" {
  name = "data-pipeline-policy"
  role = aws_iam_role.data_pipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["batch:SubmitJob", "batch:DescribeJobs", "batch:ListJobs"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          module.s3_data_pipeline.bucket_arn,
          "${module.s3_data_pipeline.bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Groups for monitoring
resource "aws_cloudwatch_log_group" "data_pipeline_logs" {
  name              = "/aws/data-pipeline"
  retention_in_days = 14
}

# IAM Role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "data-pipeline-lambda-role"

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

# IAM Policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "data-pipeline-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.s3_data_pipeline.bucket_arn,
          "${module.s3_data_pipeline.bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "batch:SubmitJob",
          "batch:DescribeJobs"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/data-pipeline-review-crawler"
  retention_in_days = 14
}

data "archive_file" "review_crawler_trigger_zip" {
  type        = "zip"
  source_dir  = "${path.module}/run_review_crawl_batch"
  output_path = "${path.module}/lambda_function.zip"
}

# Lambda function for S3 trigger
resource "aws_lambda_function" "review_crawler_trigger" {
  filename      = data.archive_file.review_crawler_trigger_zip.output_path
  function_name = "data-pipeline-review-crawler-trigger"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.handler"
  runtime       = "python3.9"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      BATCH_JOB_QUEUE             = module.batch.review_job_queue_name
      BATCH_JOB_DEFINITION        = module.batch.review_job_definition_name
      RESTAURANT_BUCKET_DIRECTORY = var.restaurant_bucket_directory
      S3_BUCKET_NAME              = var.S3_bucket_name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy.lambda_policy
  ]
}

# S3 trigger for restaurant directory
resource "aws_s3_bucket_notification" "restaurant_trigger" {
  bucket = module.s3_data_pipeline.bucket_id

  lambda_function {
    lambda_function_arn = aws_lambda_function.review_crawler_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "${var.restaurant_bucket_directory}/"
  }

  depends_on = [aws_lambda_permission.s3_trigger]
}

# Lambda permission for S3 trigger
resource "aws_lambda_permission" "s3_trigger" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.review_crawler_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.s3_data_pipeline.bucket_arn
}
