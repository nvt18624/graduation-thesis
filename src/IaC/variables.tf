variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "aws_profile" {
  description = "AWS CLI profile name"
  type        = string
  default     = "default"
}

variable "ami_id" {
  description = "AMI ID for all EC2 instances (Ubuntu in ap-southeast-1)"
  type        = string
  default     = "ami-00d8fc944fb171e29"
}

variable "key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
  default     = "my-aws-key"
}

# ── Network ───────────────────────────────────────────────────────────────────
variable "network_name" {
  description = "VPC and resource name prefix"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet 1 CIDR (ALB, Bastion, NLB, NAT)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_az" {
  type    = string
  default = "ap-southeast-1a"
}

variable "public_subnet_2_cidr" {
  description = "Public subnet 2 CIDR – ALB HA (AWS requires 2 AZs)"
  type        = string
  default     = "10.0.6.0/24"
}

variable "public_subnet_2_az" {
  type    = string
  default = "ap-southeast-1b"
}

variable "private_app_subnet_cidr" {
  description = "Private App subnet CIDR – app EC2 instances"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_app_subnet_az" {
  type    = string
  default = "ap-southeast-1a"
}

variable "private_siem_subnet_cidr" {
  description = "Private SIEM subnet CIDR – Elasticsearch, Kibana, Logstash"
  type        = string
  default     = "10.0.3.0/24"
}

variable "private_siem_subnet_az" {
  type    = string
  default = "ap-southeast-1a"
}

variable "private_data_subnet_cidr" {
  description = "Private Data subnet CIDR – DB, S3/ECR via VPC endpoints (no internet)"
  type        = string
  default     = "10.0.4.0/24"
}

variable "private_data_subnet_az" {
  type    = string
  default = "ap-southeast-1a"
}

# ── Security ──────────────────────────────────────────────────────────────────
variable "admin_cidr_blocks" {
  description = "Trusted admin CIDR(s) allowed to SSH into bastion"
  type        = list(string)
}

variable "onpremise_cidr_blocks" {
  description = "On-premise network CIDR(s) allowed to push logs to NLB (5044, 8080)"
  type        = list(string)
}

# ── Load Balancers ────────────────────────────────────────────────────────────
# ── IAM ───────────────────────────────────────────────────────────────────────
variable "log_s3_bucket_arns" {
  description = "S3 bucket ARNs Logstash is allowed to read"
  type        = list(string)
  default     = []
}

# ── Apps and Dev Users ────────────────────────────────────────────────────────
variable "apps" {
  description = "Apps to deploy – each gets 1 ECR repo + security group"
  type = map(object({
    app_port = number
  }))
  default = {}
}

variable "dev_users" {
  description = "Dev users and the apps they are allowed to deploy (least privilege)"
  type = map(object({
    allowed_apps = list(string)
  }))
  default = {}
}
