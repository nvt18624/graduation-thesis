data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Package Lambda code ───────────────────────────────────────────────────────

data "archive_file" "inference_lambda" {
  type        = "zip"
  source_file = "${path.module}/../../../ml/inference_lambda/handler.py"
  output_path = "${path.module}/inference_lambda.zip"
}

# ── IAM Role for Lambda ───────────────────────────────────────────────────────

resource "aws_iam_role" "inference_lambda" {
  name = "${var.prefix}-anomaly-inference-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.prefix}-anomaly-inference-role" }
}

resource "aws_iam_role_policy" "inference_lambda" {
  name = "${var.prefix}-anomaly-inference-policy"
  role = aws_iam_role.inference_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadModelAndLogs"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket}",
          "arn:aws:s3:::${var.s3_bucket}/*",
        ]
      },
      {
        Sid      = "InvokeRollbackLambda"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [var.rollback_lambda_arn]
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [aws_sns_topic.anomaly_alert.arn]
      },
      {
        Sid    = "SSMPromoteStableTag"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:PutParameter"]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.prefix}/*/pending-tag",
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.prefix}/*/stable-tag",
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

# ── Lambda function ───────────────────────────────────────────────────────────

resource "aws_lambda_function" "inference" {
  function_name    = "${var.prefix}-anomaly-inference"
  role             = aws_iam_role.inference_lambda.arn
  filename         = data.archive_file.inference_lambda.output_path
  source_code_hash = data.archive_file.inference_lambda.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 512   # need RAM to load model + numpy

  layers = [var.sklearn_layer_arn]  # scikit-learn + numpy layer

  environment {
    variables = {
      S3_BUCKET           = var.s3_bucket
      MODEL_KEY           = "model/auth_anomaly_detector.pkl"
      META_KEY            = "model/auth_anomaly_metadata.json"
      WINDOW_MINUTES      = tostring(var.window_minutes)
      ROLLBACK_LAMBDA_ARN = var.rollback_lambda_arn
      SNS_TOPIC_ARN       = aws_sns_topic.anomaly_alert.arn
      PREFIX              = var.prefix
      APPS                = join(",", var.apps)
    }
  }

  tags = { Name = "${var.prefix}-anomaly-inference" }
}

# ── SNS Topic for alert ───────────────────────────────────────────────────────

resource "aws_sns_topic" "anomaly_alert" {
  name = "${var.prefix}-anomaly-alert"
  tags = { Name = "${var.prefix}-anomaly-alert" }
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.anomaly_alert.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── EventBridge Schedule: trigger each N minute ─────────────────────────────────

resource "aws_cloudwatch_event_rule" "inference_schedule" {
  name                = "${var.prefix}-anomaly-inference-schedule"
  description         = "Trigger anomaly inference every ${var.window_minutes} minutes"
  schedule_expression = "rate(${var.window_minutes} minutes)"

  tags = { Name = "${var.prefix}-anomaly-inference-schedule" }
}

resource "aws_cloudwatch_event_target" "inference_lambda" {
  rule = aws_cloudwatch_event_rule.inference_schedule.name
  arn  = aws_lambda_function.inference.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inference.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.inference_schedule.arn
}
