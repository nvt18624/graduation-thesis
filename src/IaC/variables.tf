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

//network
variable "network_name" {}
variable "vpc_cidr" {}
variable "subnet_2_name" {}
variable "subnet_2_range" {}
variable "subnet_2_az" {}


