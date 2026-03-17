variable "network_name" {
  description = "VPC and resource name prefix"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "region" {
  description = "AWS region (used for VPC endpoint service names)"
  type        = string
  default     = "ap-southeast-1"
}

# ── Public Subnet 1 (primary: ALB, Bastion, NLB, NAT) ────────────────────────
variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "public_subnet_az" {
  type    = string
  default = "ap-southeast-1a"
}

# ── Public Subnet 2 (ALB HA – AWS ALB requires subnets in ≥ 2 AZs) ───────────
variable "public_subnet_2_cidr" {
  type    = string
  default = "10.0.6.0/24"
}

variable "public_subnet_2_az" {
  type    = string
  default = "ap-southeast-1b"
}

# ── Private App Subnet (10.0.2.0/24) ─────────────────────────────────────────
variable "private_app_subnet_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "private_app_subnet_az" {
  type    = string
  default = "ap-southeast-1a"
}

# ── Private SIEM Subnet (10.0.3.0/24) ────────────────────────────────────────
variable "private_siem_subnet_cidr" {
  type    = string
  default = "10.0.3.0/24"
}

variable "private_siem_subnet_az" {
  type    = string
  default = "ap-southeast-1a"
}

# ── Private Data Subnet (10.0.4.0/24) ────────────────────────────────────────
variable "private_data_subnet_cidr" {
  type    = string
  default = "10.0.4.0/24"
}

variable "private_data_subnet_az" {
  type    = string
  default = "ap-southeast-1a"
}
