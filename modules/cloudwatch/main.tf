variable "lambda_function_name" {
  description = "Name of the Lambda function for log group"
  type        = string
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 7
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.lambda_logs.name
}
