variable "prefix" {
  description = "Prefix for naming IAM resources"
  type        = string
}

variable "log_s3_bucket_arns" {
  description = "S3 bucket ARNs Logstash" 
  type        = list(string)
  default     = []
}
