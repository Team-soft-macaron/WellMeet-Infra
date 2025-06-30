provider "aws" {
  region = "ap-northeast-2"
}

module "ecr" {
  source                         = "./modules/ecr"
  ecr_review_repository_name     = "review-crawler"
  ecr_restaurant_repository_name = "restaurant-crawler"
  ecr_atmosphere_repository_name = "atmosphere-classifier"
}

module "iam" {
  source                = "./modules/iam"
  lambda_role_name      = "review-crawler-lambda-role"
  restaurant_bucket_arn = module.s3.restaurant_bucket_arn
  review_bucket_arn     = module.s3.review_bucket_arn
}

module "lambda" {
  source = "./modules/lambda"
  # lambda_function_name  = "review-crawler"
  # lambda_role_arn       = module.iam.lambda_role_arn
  # review_image_uri      = module.ecr.review_image_uri
  restaurant_bucket_id  = module.s3.restaurant_bucket_id
  s3_review_bucket_name = var.s3_review_bucket_name
  aws_access_key_id     = var.aws_access_key_id
  aws_secret_access_key = var.aws_secret_access_key
  aws_region_env        = var.aws_region_env
  place_id              = var.place_id

  # New review classifier Lambda
  atmosphere_function_name = "atmosphere-classifier"
  atmosphere_role_arn      = module.iam.lambda_role_arn
  atmosphere_image_uri     = module.ecr.atmosphere_image_uri
  review_bucket_id         = module.s3.review_bucket_id
  review_bucket_arn        = module.s3.review_bucket_arn
  atmosphere_bucket_id     = module.s3.atmosphere_bucket_id
  # atmosphere_bucket_arn    = module.s3.atmosphere_bucket_arn
  output_bucket_name = "naver-map-review-atmosphere"
}

module "s3" {
  source                          = "./modules/s3"
  restaurant_bucket_name          = "naver-map-restaurant"
  review_bucket_name              = "naver-map-review"
  atmosphere_bucket_name          = "naver-map-review-atmosphere"
  atmosphere_lambda_function_arn  = module.lambda.atmosphere_function_arn
  atmosphere_lambda_permission_id = module.lambda.atmosphere_permission_id
}

module "cloudwatch" {
  source               = "./modules/cloudwatch"
  lambda_function_name = module.lambda.atmosphere_function_name
}

# module "ec2" {
#   source = "./modules/ec2"
#   ami_id = "ami-0662f4965dfc70aca"
#   # instance_type is optional, defaults to t3.micro
# }
