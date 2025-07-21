module "s3_data_pipeline" {
  source      = "../s3"
  bucket_name = var.S3_bucket_name
}
# # 식당 크롤링 결과 저장
# module "s3_restaurant" {
#   source              = "../s3"
#   bucket_name         = "naver-map-restaurant"
# }

# # 리뷰 크롤링 결과 저장
# module "s3_review" {
#   source              = "../s3"
#   bucket_name         = "naver-map-review"
# }

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

resource "aws_iam_role" "lambda_extract_role" {
  name = "lambda-extract-place-ids-role"

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
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.extract_place_ids.arn
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

resource "aws_iam_role_policy" "lambda_extract_policy" {
  name = "lambda-extract-place-ids-policy"
  role = aws_iam_role.lambda_extract_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${module.s3_data_pipeline.bucket_arn}/*"
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

resource "aws_lambda_function" "extract_place_ids" {
  filename         = data.archive_file.extract_place_ids_zip.output_path
  function_name    = "extract-place-ids-function"
  role             = aws_iam_role.lambda_extract_role.arn
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
# Review Crawler Job Queue
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
# Step Functions State Machine
resource "aws_sfn_state_machine" "crawling_pipeline" {
  name     = "restaurant-crawling-pipeline"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = jsonencode({
    Comment = "Restaurant and Review Crawling Pipeline"
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
        Next       = "CrawlReviews"
      }

      CrawlReviews = {
        Type           = "Map"
        ItemsPath      = "$.extractedResult.placeIds"
        MaxConcurrency = 10

        Iterator = {
          StartAt = "CrawlSingleRestaurantReviews"
          States = {
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
                      "Value.$" = "$"
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
              End = true
            }
          }
        }
        End = true
      }
    }
  })
}
