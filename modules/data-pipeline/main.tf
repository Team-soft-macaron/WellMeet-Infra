# 데이터 파이프라인 전용 S3 버킷
module "s3_data_pipeline" {
  source      = "../s3"
  bucket_name = var.S3_bucket_name
}

# 크롤링 도커 이미지 ECR 저장소
module "ecr_restaurant" {
  source          = "../ecr"
  repository_name = "restaurant-crawler"
}

module "ecr_review" {
  source          = "../ecr"
  repository_name = "review-crawler"
}

# 배치 작업용 보안 그룹
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

# 크롤링 작업용 AWS Batch 모듈
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
  embedding_queue_url                   = data.aws_sqs_queue.embedding_queue.url
  embedding_queue_arn                   = aws_sqs_queue.embedding_queue.arn
}

# 데이터 파이프라인 작업용 IAM 역할
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

# 데이터 파이프라인 작업용 IAM 정책
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

# 모니터링용 CloudWatch 로그 그룹
resource "aws_cloudwatch_log_group" "data_pipeline_logs" {
  name              = "/aws/data-pipeline"
  retention_in_days = 14
}

# Lambda 함수용 IAM 역할
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

# Lambda VPC 실행 권한을 위한 관리형 정책 연결
resource "aws_iam_role_policy_attachment" "lambda_vpc_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Lambda 함수용 IAM 정책
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
          "s3:PutObject",
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
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:SendMessage"
        ]
        Resource = [
          aws_sqs_queue.embedding_queue.arn,
          aws_sqs_queue.save_restaurant_metadata_queue.arn,
          aws_sqs_queue.save_restaurant_vector_queue.arn
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
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda용 CloudWatch 로그 그룹
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/data-pipeline-review-crawler"
  retention_in_days = 14
}

data "archive_file" "review_crawler_trigger_zip" {
  type        = "zip"
  source_dir  = "${path.module}/run_review_crawl_batch"
  output_path = "${path.module}/lambda_function.zip"
}

# S3 트리거용 Lambda 함수
resource "aws_lambda_function" "review_crawler_trigger" {
  filename         = data.archive_file.review_crawler_trigger_zip.output_path
  function_name    = "data-pipeline-review-crawler-trigger"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.9"
  timeout          = 300
  memory_size      = 512
  source_code_hash = data.archive_file.review_crawler_trigger_zip.output_base64sha256

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

# 식당 디렉토리용 S3 트리거
resource "aws_s3_bucket_notification" "restaurant_trigger" {
  bucket = module.s3_data_pipeline.bucket_id

  lambda_function {
    lambda_function_arn = aws_lambda_function.review_crawler_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "${var.restaurant_bucket_directory}/"
  }

  depends_on = [aws_lambda_permission.s3_trigger]
}

# S3 트리거용 Lambda 권한
resource "aws_lambda_permission" "s3_trigger" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.review_crawler_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.s3_data_pipeline.bucket_arn
}


# 임베딩 처리용 SQS 큐
resource "aws_sqs_queue" "embedding_queue" {
  name                       = "data-pipeline-embedding-queue"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 345600 # 4 days
  receive_wait_time_seconds  = 20     # Long polling
  visibility_timeout_seconds = 900    # 15 minutes for Lambda processing

  tags = {
    Name = "data-pipeline-embedding-queue"
  }
}

data "aws_sqs_queue" "embedding_queue" {
  name = "data-pipeline-embedding-queue"
}

# 식당 메타데이터 저장 SQS 큐
resource "aws_sqs_queue" "save_restaurant_metadata_queue" {
  name                       = "data-pipeline-save-restaurant-metadata-queue"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 345600 # 4 days
  receive_wait_time_seconds  = 20     # Long polling
  visibility_timeout_seconds = 900    # 15 minutes for Lambda processing

  tags = {
    Name = "data-pipeline-save-restaurant-metadata-queue"
  }
}


# 식당 벡터 저장 SQS 큐
resource "aws_sqs_queue" "save_restaurant_vector_queue" {
  name                       = "data-pipeline-save-restaurant-vector-queue"
  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 345600 # 4 days
  receive_wait_time_seconds  = 20     # Long polling
  visibility_timeout_seconds = 900    # 15 minutes for Lambda processing

  tags = {
    Name = "data-pipeline-save-restaurant-vector-queue"
  }
}

# 임베딩 생성 Lambda용 CloudWatch 로그 그룹
resource "aws_cloudwatch_log_group" "create_embedding_lambda_logs" {
  name              = "/aws/lambda/data-pipeline-create-embedding"
  retention_in_days = 14
}

# 임베딩 생성 Lambda용 아카이브 파일
data "archive_file" "create_embedding_zip" {
  type        = "zip"
  source_file = "${path.module}/create-embedding/lambda_function.mjs"
  output_path = "${path.module}/create-embedding.zip"
}

# 임베딩 생성 Lambda 함수
resource "aws_lambda_function" "create_embedding" {
  filename         = data.archive_file.create_embedding_zip.output_path
  function_name    = "data-pipeline-create-embedding"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.handler"
  runtime          = "nodejs18.x"
  timeout          = 900 # 15 minutes
  memory_size      = 1024
  source_code_hash = data.archive_file.create_embedding_zip.output_base64sha256

  environment {
    variables = {
      S3_BUCKET_NAME             = var.S3_bucket_name
      S3_REVIEW_BUCKET_DIRECTORY = var.review_bucket_directory
      OPENAI_API_KEY             = var.openai_api_key
      SAVE_RESTAURANT_QUEUE_URL  = aws_sqs_queue.save_restaurant_metadata_queue.url
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.create_embedding_lambda_logs,
    aws_iam_role_policy.lambda_policy
  ]
}

# Lambda용 SQS 이벤트 소스 매핑
resource "aws_lambda_event_source_mapping" "sqs_embedding_trigger" {
  event_source_arn = aws_sqs_queue.embedding_queue.arn
  function_name    = aws_lambda_function.create_embedding.arn
  batch_size       = 10
  enabled          = true
}

# 식당 메타데이터 저장 Lambda용 CloudWatch 로그 그룹
resource "aws_cloudwatch_log_group" "save_restaurant_metadata_lambda_logs" {
  name              = "/aws/lambda/data-pipeline-save-restaurant-metadata"
  retention_in_days = 14
}

# 식당 메타데이터 저장 Lambda용 아카이브 파일
data "archive_file" "save_restaurant_metadata_zip" {
  type        = "zip"
  source_dir  = "${path.module}/save-restaurant-metadata"
  output_path = "${path.module}/save-restaurant-metadata.zip"
}

# 식당 메타데이터 저장 Lambda 함수
resource "aws_lambda_function" "save_restaurant_metadata" {
  filename         = data.archive_file.save_restaurant_metadata_zip.output_path
  function_name    = "data-pipeline-save-restaurant-metadata"
  role             = aws_iam_role.lambda_role.arn # 기존 역할 사용
  handler          = "lambda_function.handler"
  runtime          = "python3.9"
  timeout          = 900
  memory_size      = 1024
  source_code_hash = data.archive_file.save_restaurant_metadata_zip.output_base64sha256
  layers           = [aws_lambda_layer_version.db_layer.arn]

  # VPC 설정 추가
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.api_server_security_group_id]
  }

  environment {
    variables = {
      S3_BUCKET_NAME             = var.S3_bucket_name
      EMBEDDING_BUCKET_DIRECTORY = "embedding"
      RESTAURANT_DB_HOST         = var.restaurant_db_host
      RESTAURANT_DB_USER         = var.restaurant_db_user
      RESTAURANT_DB_PASSWORD     = var.restaurant_db_password
      RESTAURANT_DB_NAME         = var.restaurant_db_name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.save_restaurant_metadata_lambda_logs,
    aws_iam_role_policy.lambda_policy
  ]
}

# Lambda용 SQS 이벤트 소스 매핑
resource "aws_lambda_event_source_mapping" "sqs_save_restaurant_trigger" {
  event_source_arn = aws_sqs_queue.save_restaurant_metadata_queue.arn
  function_name    = aws_lambda_function.save_restaurant_metadata.arn
  batch_size       = 1 # 한 번에 하나씩 처리
  enabled          = true
}

# Outbox 폴링 Lambda용 CloudWatch 로그 그룹
resource "aws_cloudwatch_log_group" "outbox_polling_lambda_logs" {
  name              = "/aws/lambda/data-pipeline-outbox-polling"
  retention_in_days = 14
}

# Outbox 폴링 Lambda용 아카이브 파일
data "archive_file" "outbox_polling_zip" {
  type        = "zip"
  source_dir  = "${path.module}/outbox-polling"
  output_path = "${path.module}/outbox-polling.zip"
}

# Outbox 폴링 Lambda 함수
resource "aws_lambda_function" "outbox_polling" {
  filename         = data.archive_file.outbox_polling_zip.output_path
  function_name    = "data-pipeline-outbox-polling"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.9"
  timeout          = 300
  memory_size      = 512
  source_code_hash = data.archive_file.outbox_polling_zip.output_base64sha256
  layers           = [aws_lambda_layer_version.db_layer.arn]

  # VPC 설정 추가
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.api_server_security_group_id]
  }

  environment {
    variables = {
      RESTAURANT_DB_HOST     = var.restaurant_db_host
      RESTAURANT_DB_USER     = var.restaurant_db_user
      RESTAURANT_DB_PASSWORD = var.restaurant_db_password
      RESTAURANT_DB_NAME     = var.restaurant_db_name
      OUTBOX_QUEUE_URL       = aws_sqs_queue.save_restaurant_vector_queue.url
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.outbox_polling_lambda_logs,
    aws_iam_role_policy.lambda_policy
  ]
}

# Vector 저장 Lambda용 CloudWatch 로그 그룹
resource "aws_cloudwatch_log_group" "save_vector_lambda_logs" {
  name              = "/aws/lambda/data-pipeline-save-vector"
  retention_in_days = 14
}

# Vector 저장 Lambda용 아카이브 파일
data "archive_file" "save_vector_zip" {
  type        = "zip"
  source_dir  = "${path.module}/save-vector"
  output_path = "${path.module}/save-vector.zip"
}

# Vector 저장 Lambda 함수
resource "aws_lambda_function" "save_vector" {
  filename         = data.archive_file.save_vector_zip.output_path
  function_name    = "data-pipeline-save-vector"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.9"
  timeout          = 900
  memory_size      = 1024
  source_code_hash = data.archive_file.save_vector_zip.output_base64sha256
  layers           = [aws_lambda_layer_version.db_layer.arn]

  # VPC 설정 추가
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.api_server_security_group_id]
  }

  environment {
    variables = {
      S3_BUCKET_NAME             = var.S3_bucket_name
      EMBEDDING_BUCKET_DIRECTORY = "embedding"
      RECOMMEND_DB_HOST          = var.recommend_db_host
      RECOMMEND_DB_PORT          = var.recommend_db_port
      RECOMMEND_DB_NAME          = var.recommend_db_name
      RECOMMEND_DB_USER          = var.recommend_db_user
      RECOMMEND_DB_PASSWORD      = var.recommend_db_password
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.save_vector_lambda_logs,
    aws_iam_role_policy.lambda_policy
  ]
}

# Vector 저장 Lambda용 SQS 이벤트 소스 매핑
resource "aws_lambda_event_source_mapping" "sqs_save_vector_trigger" {
  event_source_arn = aws_sqs_queue.save_restaurant_vector_queue.arn
  function_name    = aws_lambda_function.save_vector.arn
  batch_size       = 1 # 한 번에 하나씩 처리
  enabled          = true
}

# EventBridge Rule - 1시간마다 outbox 폴링
resource "aws_cloudwatch_event_rule" "outbox_polling_schedule" {
  name                = "outbox-polling-schedule"
  description         = "Trigger outbox polling Lambda every hour"
  schedule_expression = "rate(1 hour)"
}

# EventBridge Target - outbox 폴링 Lambda
resource "aws_cloudwatch_event_target" "outbox_polling_target" {
  rule      = aws_cloudwatch_event_rule.outbox_polling_schedule.name
  target_id = "OutboxPollingLambda"
  arn       = aws_lambda_function.outbox_polling.arn
}

# EventBridge에서 Lambda 호출 권한
resource "aws_lambda_permission" "eventbridge_outbox_polling" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.outbox_polling.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.outbox_polling_schedule.arn
}

# Lambda Layer 생성 (pymysql 포함)
resource "aws_lambda_layer_version" "db_layer" {
  filename            = "${path.module}/lambda-layer/lambda-layer.zip"
  layer_name          = "data-pipeline-db-layer"
  description         = "Lambda Layer for dependency"
  compatible_runtimes = ["python3.9"]
  source_code_hash    = filebase64sha256("${path.module}/lambda-layer/lambda-layer.zip")
}
