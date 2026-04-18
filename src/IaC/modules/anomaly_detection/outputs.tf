output "inference_lambda_arn" {
  value = aws_lambda_function.inference.arn
}

output "sns_topic_arn" {
  value = aws_sns_topic.anomaly_alert.arn
}
