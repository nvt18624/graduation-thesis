variable "network_name" {}

variable "vpc_cidr" {}

variable "subnet_2_name" {}

variable "subnet_2_range" {}

variable "subnet_2_az" {}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "public_subnet_az" {
  type    = string
  default = "ap-southeast-1a"
}
