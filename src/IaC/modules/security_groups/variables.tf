variable "prefix" {
  description = "Prefix for naming security groups"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks allowed SSH access "
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
