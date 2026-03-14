variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-southeast-1"
}

variable "aws_profile" {
  description = "AWS CLI profile name to use"
  type        = string
  default     = "default"
}

// network
variable "network_name" {}
variable "vpc_cidr" {}
variable "subnet_2_name" {}
variable "subnet_2_range" {}
variable "subnet_2_az" {}

variable "private_subnet_cidr" {
  description = "CIDR for private subnet (Elasticsearch)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_subnet_az" {
  description = "AZ cho private subnet"
  type        = string
  default     = "ap-southeast-1a"
}

// security groups
variable "admin_cidr_blocks" {
  description = "CIDR blocks is allowed SSH to instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

// IAM
variable "log_s3_bucket_arns" {
  description = "S3 bucket ARNs Logstash is readed" 
  type        = list(string)
  default     = []
}

// Apps and Dev users
variable "apps" {
  description = "List applications need deploy (each app have 1 ECR repo + SG )"
  type = map(object({
    app_port = number
  }))
  default = {}
}

variable "dev_users" {
  description = "Dev users and apps that they are allowd to deploy (least privilege)"
  type = map(object({
    allowed_apps = list(string)
  }))
  default = {}
}
