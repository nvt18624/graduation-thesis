variable "prefix" {
  description = "Prefix for naming security groups"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block – used to restrict ELK and Logstash ports to internal traffic only"
  type        = string
  default     = "10.0.0.0/16"
}

variable "admin_cidr_blocks" {
  description = "Trusted admin CIDR blocks allowed to SSH into bastion"
  type        = list(string)
}

variable "onpremise_cidr_blocks" {
  description = "On-premise network CIDR blocks allowed to push logs to NLB (ports 5044 and 8080)"
  type        = list(string)
}

variable "app_sg_ids" {
  description = "Security Group IDs of app instances – granted PostgreSQL access to DB"
  type        = list(string)
  default     = []
}
