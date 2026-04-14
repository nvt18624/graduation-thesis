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

variable "app_ports" {
  description = "Map of app name → port; each entry gets 1 listener + target group on the ALB"
  type        = map(number)
  default     = {}
}

variable "app_instances" {
  description = "Map of app name → instance ID; registers the instance into the matching target group"
  type        = map(string)
  default     = {}
}
