output "external_ips" {
  value = [for instance in aws_instance.default : instance.public_ip]
}

output "internal_ips" {
  value = [for instance in aws_instance.default : instance.private_ip]
}

output "instance_ids" {
  value = [for instance in aws_instance.default : instance.id]
}

