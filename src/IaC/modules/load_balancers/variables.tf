variable "prefix" {
  description = "Name prefix for all load balancer resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "alb_sg_id" {
  description = "Security Group ID for the ALB"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB (must be in ≥ 2 AZs)"
  type        = list(string)
}

variable "kibana_instance_id" {
  description = "EC2 instance ID of Kibana – registered as ALB target on /kibana*"
  type        = string
}
