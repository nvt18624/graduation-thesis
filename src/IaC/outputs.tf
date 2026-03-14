output "elas_public_ips" {
  value = module.elas.external_ips
}

output "elas_private_ips" {
  value = module.elas.internal_ips
}

output "kibana_public_ips" {
  value = module.kibana.external_ips
}

output "kibana_private_ips" {
  value = module.kibana.internal_ips
}

output "logstash_public" {
  value = module.logstash.external_ips
}

output "logstash_private" {
  value = module.logstash.internal_ips
}

output "subnet_link" {
  value = [
    module.network.subnet_2
  ]
}

output "internet_gateway" {
  value = module.network.internet_gateway_id
}

output "public_route_table_id" {
  value = module.network.public_route_table_id
}

output "private_subnet_id" {
  value = module.network.private_subnet_id
}

output "nat_gateway_id" {
  value = module.network.nat_gateway_id
}

output "sg_elasticsearch_id" {
  value = module.security_groups.sg_elasticsearch_id
}

output "sg_kibana_id" {
  value = module.security_groups.sg_kibana_id
}

output "sg_logstash_id" {
  value = module.security_groups.sg_logstash_id
}

output "ecr_urls" {
  description = "ECR repository URLs with each app – set to GitLab CI/CD Variables"
  value       = module.iam_users.ecr_urls
}

output "app_sg_ids" {
  description = "Security Group ID for each app"
  value       = module.iam_users.app_sg_ids
}

output "user_app_mapping" {
  description = "Mapping user -> apps" 
  value       = module.iam_users.user_app_mapping
}

# Sensitive – Run: terraform output -json user_credentials
output "user_credentials" {
  description = "Access keys for each dev (sensitive) – run: terraform output -json user_credentials"
  value       = module.iam_users.user_credentials
  sensitive   = true
}
