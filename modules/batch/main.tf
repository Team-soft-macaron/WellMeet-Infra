# AWS Batch 서비스용 IAM 역할
resource "aws_iam_role" "batch_service_role" {
  name = "batch-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "batch.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "batch_service_role_policy" {
  role       = aws_iam_role.batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# ECS 태스크 실행용 IAM 역할
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "batch-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 배치 작업용 IAM 역할 
resource "aws_iam_role" "batch_job_role" {
  name = "batch-job-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# 배치 작업 역할에 필요한 정책 추가
resource "aws_iam_role_policy" "batch_job_policy" {
  name = "batch-job-policy"
  role = aws_iam_role.batch_job_role.id

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
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.embedding_queue_arn
      }
    ]
  })
}

# 컴퓨트 환경
resource "aws_batch_compute_environment" "fargate_spot" {
  name         = "fargate-spot-compute-env"
  type         = "MANAGED"
  state        = "ENABLED"
  service_role = aws_iam_role.batch_service_role.arn

  compute_resources {
    type      = "FARGATE_SPOT"
    max_vcpus = 256

    subnets            = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  depends_on = [
    aws_iam_role_policy_attachment.batch_service_role_policy
  ]
}

# 작업 큐
resource "aws_batch_job_queue" "restaurant_crawler" {
  name     = "fargate-spot-restaurant-crawler-job-queue"
  state    = "ENABLED"
  priority = 1
  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.fargate_spot.arn
  }
}
resource "aws_batch_job_queue" "review_crawler" {
  name     = "fargate-spot-review-crawler-job-queue"
  state    = "ENABLED"
  priority = 1
  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.fargate_spot.arn
  }
}

# 작업 정의
resource "aws_batch_job_definition" "review_crawler" {
  name = "batch-review-job-definition"
  type = "container"

  platform_capabilities = ["FARGATE"]

  container_properties = jsonencode({
    image = var.review_crawler_ecr_repository_url

    fargatePlatformConfiguration = {
      platformVersion = "LATEST"
    }

    resourceRequirements = [
      {
        type  = "VCPU"
        value = "2"
      },
      {
        type  = "MEMORY"
        value = "8192" # 8GB in MB
      }
    ]

    executionRoleArn = aws_iam_role.ecs_task_execution_role.arn
    jobRoleArn       = aws_iam_role.batch_job_role.arn

    # 실행 제한 시간 30분
    timeout = {
      attemptDurationSeconds = 1800
    }

    # public IP 할당하여 인터넷 연결 허용
    networkConfiguration = {
      assignPublicIp = "ENABLED"
    }

    # 로그 설정
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/aws/batch/review-crawler"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "batch-job"
      }
    }

    environment = [
      {
        name  = "AWS_REGION"
        value = var.aws_region
      },
      {
        name  = "S3_BUCKET_NAME"
        value = var.S3_bucket_name
      },
      {
        name  = "PYTHONUNBUFFERED"
        value = "1"
      },
      {
        name  = "REVIEW_BUCKET_DIRECTORY"
        value = var.review_bucket_directory
      },
      {
        name  = "SQS_QUEUE_URL"
        value = var.embedding_queue_url
      }
    ]
  })
}

resource "aws_batch_job_definition" "restaurant_crawler" {
  name = "batch-restaurant-job-definition"
  type = "container"

  platform_capabilities = ["FARGATE"]

  container_properties = jsonencode({
    image = var.restaurant_crawler_ecr_repository_url

    fargatePlatformConfiguration = {
      platformVersion = "LATEST"
    }

    resourceRequirements = [
      {
        type  = "VCPU"
        value = "2"
      },
      {
        type  = "MEMORY"
        value = "8192" # 8GB in MB
      }
    ]

    executionRoleArn = aws_iam_role.ecs_task_execution_role.arn
    jobRoleArn       = aws_iam_role.batch_job_role.arn

    # 실행 제한 시간 30분
    timeout = {
      attemptDurationSeconds = 1800
    }

    # public IP 할당하여 인터넷 연결 허용
    networkConfiguration = {
      assignPublicIp = "ENABLED"
    }

    # 로그 설정
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/aws/batch/restaurant-crawler"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "batch-job"
      }
    }

    environment = [
      {
        name  = "AWS_REGION"
        value = var.aws_region
      },
      {
        name  = "S3_BUCKET_NAME"
        value = var.S3_bucket_name
      },
      {
        name  = "PYTHONUNBUFFERED"
        value = "1"
      },
      {
        name  = "RESTAURANT_BUCKET_DIRECTORY"
        value = var.restaurant_bucket_directory
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "review_crawler_logs" {
  name              = "/aws/batch/review-crawler"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "restaurant_crawler_logs" {
  name              = "/aws/batch/restaurant-crawler"
  retention_in_days = 7
}
