provider "aws" {
  region = "ap-northeast-2"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello_world.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::naver-map-restaurant"
}

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
        Action = ["s3:GetObject", "s3:ListBucket"],
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

# Lambda 함수
resource "aws_lambda_function" "hello_world" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "hello-world-function"
  role             = aws_iam_role.lambda_batch_role.arn
  handler          = "lambda_function.handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.9"
  timeout          = 3
}

# module "iam" {
#   source           = "./modules/iam"
#   lambda_role_name = "review-crawler-lambda-role"
#   s3_read_arns     = [module.s3_restaurant.bucket_arn]
#   s3_write_arns    = [module.s3_review.bucket_arn]
# }

module "s3_restaurant" {
  source               = "./modules/s3"
  bucket_name          = "naver-map-restaurant"
  enable_notification  = true
  lambda_function_arn  = aws_lambda_function.hello_world.arn
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

module "cloudwatch" {
  source               = "./modules/cloudwatch"
  lambda_function_name = aws_lambda_function.hello_world.function_name
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

# module "ec2" {
#   source = "./modules/ec2"
#   ami_id = "ami-0662f4965dfc70aca"
#   # instance_type is optional, defaults to t3.micro
# }
