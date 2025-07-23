module "s3_data_pipeline" {
  source      = "../s3"
  bucket_name = var.S3_bucket_name
}

# 식당 크롤링 docker 이미지 저장
module "ecr_restaurant" {
  source          = "../ecr"
  repository_name = "restaurant-crawler"
}

# 리뷰 크롤링 docker 이미지 저장
module "ecr_review" {
  source          = "../ecr"
  repository_name = "review-crawler"
}
resource "aws_security_group" "batch_fargate" {
  name        = "batch-fargate-sg"
  description = "Security group for AWS Batch Fargate jobs"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

# 식당 크롤링, 리뷰 크롤링 job
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
# Step Functions IAM Role
resource "aws_iam_role" "step_functions_role" {
  name = "step-functions-crawling-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role" "lambda_function_role" {
  name = "lambda-function-role"
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

resource "aws_iam_role_policy" "step_functions_policy" {
  name = "step-functions-crawling-policy"
  role = aws_iam_role.step_functions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["batch:SubmitJob", "batch:DescribeJobs"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = [
          aws_lambda_function.extract_place_ids.arn,
          aws_lambda_function.create_category_batch.arn,
          aws_lambda_function.create_embedding_batch.arn,
          aws_lambda_function.save_embedding.arn
        ]
      },
      # 👇 이 부분을 추가
      {
        Effect = "Allow"
        Action = [
          "events:PutTargets",
          "events:PutRule",
          "events:DescribeRule"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda IAM Role

resource "aws_iam_role_policy" "lambda_function_policy" {
  name = "lambda-extract-place-ids-policy"
  role = aws_iam_role.lambda_function_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "${module.s3_data_pipeline.bucket_arn}/*",
          "${module.s3_data_pipeline.bucket_arn}"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda Function
data "archive_file" "extract_place_ids_zip" {
  type        = "zip"
  source_dir  = "${path.module}/extract_place_ids"
  output_path = "${path.module}/extract_place_ids.zip"
}

data "archive_file" "create_category_batch_zip" {
  type        = "zip"
  source_dir  = "${path.module}/create-category-batch"
  output_path = "${path.module}/create-category-batch.zip"
}

data "archive_file" "create_embedding_batch_zip" {
  type        = "zip"
  source_dir  = "${path.module}/create-embedding-batch"
  output_path = "${path.module}/create-embedding-batch.zip"
}

data "archive_file" "save_embedding_zip" {
  type        = "zip"
  source_dir  = "${path.module}/save-embedding"
  output_path = "${path.module}/save-embedding.zip"
}

data "archive_file" "save_restaurant_to_db_zip" {
  type        = "zip"
  source_dir  = "${path.module}/save_restaurant_to_db"
  output_path = "${path.module}/save_restaurant_to_db.zip"
}

resource "aws_lambda_function" "extract_place_ids" {
  filename         = data.archive_file.extract_place_ids_zip.output_path
  function_name    = "extract-place-ids-function"
  role             = aws_iam_role.lambda_function_role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.9"
  timeout          = 300
  source_code_hash = data.archive_file.extract_place_ids_zip.output_base64sha256

  environment {
    variables = {
      S3_BUCKET_NAME = module.s3_data_pipeline.bucket_name
    }
  }
}
# DB 저장 Lambda
resource "aws_lambda_function" "save_restaurant_to_db" {
  filename         = data.archive_file.save_restaurant_to_db_zip.output_path
  function_name    = "save-restaurant-to-db-function"
  role             = aws_iam_role.access_rds_role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.9"
  timeout          = 300
  source_code_hash = data.archive_file.save_restaurant_to_db_zip.output_base64sha256

  environment {
    variables = {
      S3_BUCKET_NAME         = module.s3_data_pipeline.bucket_name
      RESTAURANT_DB_HOST     = var.restaurant_db_host
      RESTAURANT_DB_USER     = var.restaurant_db_user
      RESTAURANT_DB_PASSWORD = var.restaurant_db_password
      RESTAURANT_DB_NAME     = var.restaurant_db_name
      RECOMMEND_DB_HOST      = var.recommend_db_host
      RECOMMEND_DB_USER      = var.recommend_db_user
      RECOMMEND_DB_PASSWORD  = var.recommend_db_password
      RECOMMEND_DB_NAME      = var.recommend_db_name
      RECOMMEND_DB_PORT      = var.recommend_db_port
    }
  }
  vpc_config {
    subnet_ids         = var.private_subnets_for_lambda
    security_group_ids = [aws_security_group.save_restaurant_to_db_lambda_sg.id]
  }
  layers = [aws_lambda_layer_version.db_layer.arn]
}


resource "aws_lambda_function" "create_category_batch" {
  filename         = data.archive_file.create_category_batch_zip.output_path
  function_name    = "create-category-batch-function"
  role             = aws_iam_role.lambda_function_role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.9"
  timeout          = 300
  source_code_hash = data.archive_file.create_category_batch_zip.output_base64sha256
  architectures    = ["arm64"]

  environment {
    variables = {
      REVIEW_BUCKET_DIRECTORY = var.review_bucket_directory
      S3_BUCKET_NAME          = module.s3_data_pipeline.bucket_name
      OPENAI_API_KEY          = var.openai_api_key
    }
  }
}

resource "aws_lambda_function" "create_embedding_batch" {
  filename         = data.archive_file.create_embedding_batch_zip.output_path
  function_name    = "create-embedding-batch-function"
  role             = aws_iam_role.lambda_function_role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.9"
  timeout          = 300
  source_code_hash = data.archive_file.create_embedding_batch_zip.output_base64sha256

  environment {
    variables = {
      REVIEW_BUCKET_DIRECTORY   = var.review_bucket_directory
      CATEGORY_BUCKET_DIRECTORY = var.category_bucket_directory
      S3_BUCKET_NAME            = module.s3_data_pipeline.bucket_name
      OPENAI_API_KEY            = var.openai_api_key
    }
  }
}

resource "aws_lambda_function" "save_embedding" {
  filename         = data.archive_file.save_embedding_zip.output_path
  function_name    = "save-embedding-function"
  role             = aws_iam_role.lambda_function_role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.9"
  timeout          = 300
  source_code_hash = data.archive_file.save_embedding_zip.output_base64sha256

  environment {
    variables = {
      S3_BUCKET_NAME             = module.s3_data_pipeline.bucket_name
      CATEGORY_BUCKET_DIRECTORY  = var.category_bucket_directory
      EMBEDDING_BUCKET_DIRECTORY = var.embedding_vector_bucket_directory
      OPENAI_API_KEY             = var.openai_api_key
    }
  }
}

resource "aws_batch_job_queue" "restaurant_crawler" {
  name     = "restaurant-crawler-queue"
  state    = "ENABLED"
  priority = 1

  compute_environment_order {
    order               = 1
    compute_environment = module.batch.compute_environment_arn
  }
}
resource "aws_batch_job_queue" "review_crawler" {
  name     = "review-crawler-queue"
  state    = "ENABLED"
  priority = 1

  compute_environment_order {
    order               = 1
    compute_environment = module.batch.compute_environment_arn
  }
}

# 마지막 DB 저장을 위해 필요한 package lambda layer
resource "terraform_data" "db_layer_builder" {
  triggers_replace = {
    requirements = filemd5("${path.module}/requirements.txt")
  }

  provisioner "local-exec" {
    command = <<-EOT
      docker run --rm \
        -v ${abspath(path.module)}:/work \
        -w /work \
        --entrypoint /bin/bash \
        public.ecr.aws/lambda/python:3.9 \
        -c '
          rm -rf layer
          mkdir -p layer/python
          pip install -r requirements.txt -t layer/python --no-cache-dir
          cd layer
          yum install -y zip
          zip -r db-layer.zip python/
        '
    EOT
  }
}

# Lambda Layer 생성
resource "aws_lambda_layer_version" "db_layer" {
  filename            = "${path.module}/layer/db-layer.zip"
  layer_name          = "db-layer"
  compatible_runtimes = ["python3.9"]

  depends_on = [terraform_data.db_layer_builder]
}

resource "aws_iam_role" "access_rds_role" {
  name = "access-rds-role"
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

resource "aws_iam_role_policy" "lambda_all_permissions" {
  name = "lambda-all-permissions"
  role = aws_iam_role.access_rds_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
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
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${module.s3_data_pipeline.bucket_name}",
          "arn:aws:s3:::${module.s3_data_pipeline.bucket_name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "access_s3_role_policy" {
  name = "access-s3-role-policy"
  role = aws_iam_role.lambda_function_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "${module.s3_data_pipeline.bucket_arn}/*",
          "${module.s3_data_pipeline.bucket_arn}"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# # VPC 내에서 실행되는 Lambda를 위한 권한
# resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
#   role       = aws_iam_role.access_rds_role.name
# }

# resource "aws_iam_role_policy_attachment" "access_s3_role_policy_attachment" {
#   policy_arn = aws_iam_role_policy.lambda_function_policy.arn
#   role       = aws_iam_role.access_rds_role.name
# }
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  role       = aws_iam_role.access_rds_role.name
}

# # 최소한의 보안 그룹
resource "aws_security_group" "save_restaurant_to_db_lambda_sg" {
  name   = "lambda-sg"
  vpc_id = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_sfn_state_machine" "crawling_pipeline" {
  name     = "restaurant-crawling-pipeline"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = jsonencode({
    Comment = "Restaurant and Review Crawling Pipeline with Category and Embedding"
    StartAt = "CrawlRestaurants"

    States = {
      CrawlRestaurants = {
        Type     = "Task"
        Resource = "arn:aws:states:::batch:submitJob.sync"
        Parameters = {
          JobDefinition = module.batch.restaurant_job_definition_arn
          JobName       = "restaurant-crawling"
          JobQueue      = aws_batch_job_queue.restaurant_crawler.name
          ContainerOverrides = {
            Environment = [
              {
                Name      = "SEARCH_QUERY"
                "Value.$" = "$.query"
              },
              {
                Name  = "RESTAURANT_BUCKET_DIRECTORY"
                Value = var.restaurant_bucket_directory
              },
              {
                Name  = "S3_BUCKET_NAME"
                Value = var.S3_bucket_name
              }
            ]
          }
        }
        ResultPath = "$.batchResult"
        Next       = "ExtractPlaceIds"
      }

      ExtractPlaceIds = {
        Type     = "Task"
        Resource = aws_lambda_function.extract_place_ids.arn
        Parameters = {
          "SEARCH_QUERY.$"              = "$.query"
          "S3_BUCKET_NAME"              = var.S3_bucket_name
          "RESTAURANT_BUCKET_DIRECTORY" = var.restaurant_bucket_directory
        }
        ResultPath = "$.extractedResult"
        Next       = "ProcessEachRestaurant"
      }

      # 각 식당별로 전체 프로세스 실행
      ProcessEachRestaurant = {
        Type           = "Map"
        ItemsPath      = "$.extractedResult.placeIds"
        MaxConcurrency = 100
        ResultPath     = "$.allRestaurantsResult"

        ItemProcessor = {
          ProcessorConfig = {
            Mode = "INLINE"
          }

          StartAt = "CrawlSingleRestaurantReviews"

          States = {
            # 단일 식당 리뷰 크롤링
            CrawlSingleRestaurantReviews = {
              Type     = "Task"
              Resource = "arn:aws:states:::batch:submitJob.sync"
              Parameters = {
                JobDefinition = module.batch.review_job_definition_arn
                JobName       = "review-crawling"
                JobQueue      = aws_batch_job_queue.review_crawler.name
                ContainerOverrides = {
                  Environment = [
                    {
                      Name      = "PLACE_ID"
                      "Value.$" = "$.placeId" # 현재 place_id
                    },
                    {
                      Name  = "S3_BUCKET_NAME"
                      Value = var.S3_bucket_name
                    },
                    {
                      Name  = "REVIEW_BUCKET_DIRECTORY"
                      Value = var.review_bucket_directory
                    }
                  ]
                }
              }
              ResultPath = "$.reviewCrawlResult"
              Next       = "CreateCategoryBatchForRestaurant"
            }

            # 해당 식당의 카테고리 추출
            CreateCategoryBatchForRestaurant = {
              Type     = "Task"
              Resource = "arn:aws:states:::lambda:invoke"
              Parameters = {
                FunctionName = aws_lambda_function.create_category_batch.arn
                Payload = {
                  "S3_KEY.$" = "$.placeId"
                }
              }
              ResultSelector = {
                "statusCode.$" = "$.Payload.statusCode"
                "body.$"       = "$.Payload.body"
              }
              ResultPath = "$.categoryResult"
              Next       = "CheckCategoryAndCreateEmbedding"
            }

            # 카테고리 확인 및 임베딩 생성
            CheckCategoryAndCreateEmbedding = {
              Type     = "Task"
              Resource = "arn:aws:states:::lambda:invoke"
              Parameters = {
                FunctionName = aws_lambda_function.create_embedding_batch.arn
                Payload = {
                  "S3_KEY.$" = "$.placeId",
                  "body.$"   = "$.categoryResult.body",
                }
              }
              ResultSelector = {
                "statusCode.$" = "$.Payload.statusCode"
                "body.$"       = "$.Payload.body"
              }
              ResultPath = "$.embeddingRequestResult"
              Next       = "EvaluateEmbeddingResult"
            }

            # 임베딩 결과 평가
            EvaluateEmbeddingResult = {
              Type = "Choice"
              Choices = [
                {
                  Variable      = "$.embeddingRequestResult.statusCode"
                  NumericEquals = 202
                  Next          = "WaitForEmbedding"
                },
                {
                  Variable      = "$.embeddingRequestResult.statusCode"
                  NumericEquals = 200
                  Next          = "CheckEmbeddingAndSave"
                }
              ]
              Default = "HandleEmbeddingError"
            }

            # 임베딩 대기
            WaitForEmbedding = {
              Type    = "Wait"
              Seconds = 1800
              Next    = "CheckCategoryAndCreateEmbedding"
            }

            # 임베딩 에러 처리
            HandleEmbeddingError = {
              Type   = "Pass"
              Result = "Embedding failed"
              Next   = "RestaurantProcessComplete"
            }

            # 임베딩 확인 및 저장
            CheckEmbeddingAndSave = {
              Type     = "Task"
              Resource = "arn:aws:states:::lambda:invoke"
              Parameters = {
                FunctionName = aws_lambda_function.save_embedding.arn
                Payload = {
                  "S3_KEY.$" = "$.placeId",
                  "body.$"   = "$.embeddingRequestResult.body"
                }
              }
              ResultSelector = {
                "statusCode.$" = "$.Payload.statusCode"
                "body.$"       = "$.Payload.body"
              }
              ResultPath = "$.saveEmbeddingResult"
              Next       = "EvaluateSaveResult"
            }
            # 저장 결과 평가
            EvaluateSaveResult = {
              Type = "Choice"
              Choices = [
                {
                  Variable      = "$.saveEmbeddingResult.statusCode"
                  NumericEquals = 202
                  Next          = "WaitForSave"
                },
                {
                  Variable      = "$.saveEmbeddingResult.statusCode"
                  NumericEquals = 200
                  Next          = "RestaurantProcessComplete"
                }
              ]
              Default = "HandleSaveError"
            }

            # 저장 대기
            WaitForSave = {
              Type    = "Wait"
              Seconds = 1800
              Next    = "CheckEmbeddingAndSave"
            }

            # 저장 에러 처리
            HandleSaveError = {
              Type   = "Pass"
              Result = "Save failed"
              Next   = "RestaurantProcessComplete"
            }

            # 단일 식당 처리 완료
            RestaurantProcessComplete = {
              Type   = "Pass"
              Result = "Restaurant processing completed"
              End    = true
            }
          }
        }
        Next = "AllRestaurantsComplete"
      }

      # 모든 식당 처리 완료
      AllRestaurantsComplete = {
        Type = "Succeed"
      }
    }
  })
}
