variable "firewall_name" {}
variable "vpc_id" {}
variable "protocol" {}
variable "ports" {
  type = list(number)
}
variable "source_ranges" {
  type = list(string)
}
