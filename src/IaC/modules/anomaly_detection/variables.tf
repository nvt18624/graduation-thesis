variable "prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "s3_bucket" {
  description = "S3 bucket chứa logs và model"
  type        = string
}

variable "rollback_lambda_arn" {
  description = "ARN của Rollback Lambda"
  type        = string
}

variable "sklearn_layer_arn" {
  description = "ARN của Lambda Layer chứa scikit-learn + numpy"
  type        = string
}

variable "window_minutes" {
  description = "Kích thước time window (phút) - phải khớp với lúc train model"
  type        = number
  default     = 60
}

variable "apps" {
  description = "Danh sách app cần rollback khi phát hiện anomaly"
  type        = list(string)
  default     = []
}

variable "alert_email" {
  description = "Email nhận SNS alert (để trống nếu không cần)"
  type        = string
  default     = ""
}
