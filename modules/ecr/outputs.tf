# Outputs
output "repository_url" {
  value = aws_ecr_repository.this.repository_url
}

output "image_uri" {
  value = "${aws_ecr_repository.this.repository_url}:latest"
}
