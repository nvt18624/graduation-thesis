variable "instance_name" {
  description = "name isntance"
  type        = string
}

variable "machine_type" {
  description = "macine type"
  type        = string
}

variable "ami_id" {
  description = "Amazon Machine Image (AMI) ID"
  type        = string
}

variable "subnetwork" {
  description = "Subnet ID in VPC"
  type        = string
}

variable "security_groups" {
  description = "List Security Group IDs"
  type        = list(string)
}

variable "key_name" {
  description = "SSH key-pair name in aws"
  type        = string
}

variable "instance_count" {
  description = "quantity, default 1"
  type        = number
  default     = 1
}

variable "internal_ip" {
  description = "private ip"
  type        = list(string)
  default     = [""]
}

variable "enable_public_ip" {
  description = "Does public ip ?"
  type        = bool
  default     = true
}

variable "file_script" {
  description = "file scirpt path"
  type        = string
  default     = ""
}
