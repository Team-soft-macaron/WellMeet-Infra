# Variables
variable "ecr_review_repository_name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "ecr_restaurant_repository_name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "ecr_atmosphere_repository_name" {
  description = "Name of the ECR repository"
  type        = string
}

resource "aws_ecr_repository" "restaurant_crawler" {
  name                 = var.ecr_restaurant_repository_name
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "restaurant_crawler" {
  repository = aws_ecr_repository.restaurant_crawler.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
resource "aws_ecr_repository" "review_crawler" {
  name                 = var.ecr_review_repository_name
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "review_crawler" {
  repository = aws_ecr_repository.review_crawler.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
resource "aws_ecr_repository" "atmosphere_classifier" {
  name                 = var.ecr_atmosphere_repository_name
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "atmosphere_classifier" {
  repository = aws_ecr_repository.atmosphere_classifier.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
# Outputs
output "review_repository_url" {
  value = aws_ecr_repository.review_crawler.repository_url
}

output "restaurant_repository_url" {
  value = aws_ecr_repository.restaurant_crawler.repository_url
}

output "atmosphere_repository_url" {
  value = aws_ecr_repository.atmosphere_classifier.repository_url
}

output "review_image_uri" {
  value = "${aws_ecr_repository.review_crawler.repository_url}:latest"
}

output "restaurant_image_uri" {
  value = "${aws_ecr_repository.restaurant_crawler.repository_url}:latest"
}

output "atmosphere_image_uri" {
  value = "${aws_ecr_repository.atmosphere_classifier.repository_url}:latest"
}
