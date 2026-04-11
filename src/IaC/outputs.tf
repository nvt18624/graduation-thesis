# ── Networking ────────────────────────────────────────────────────────────────
output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_app_subnet_id" {
  value = module.network.private_app_subnet_id
}

output "private_siem_subnet_id" {
  value = module.network.private_siem_subnet_id
}

output "private_data_subnet_id" {
  value = module.network.private_data_subnet_id
}

output "nat_gateway_id" {
  value = module.network.nat_gateway_id
}

output "internet_gateway" {
  value = module.network.internet_gateway_id
}

output "public_route_table_id" {
  value = module.network.public_route_table_id
}

output "s3_endpoint_id" {
  value = module.network.s3_endpoint_id
}

output "ecr_api_endpoint_id" {
  value = module.network.ecr_api_endpoint_id
}

output "ecr_dkr_endpoint_id" {
  value = module.network.ecr_dkr_endpoint_id
}

# ── Load Balancers ────────────────────────────────────────────────────────────
output "alb_dns_name" {
  description = "ALB DNS – app: http://<dns>/, kibana: http://<dns>/kibana"
  value       = module.load_balancers.alb_dns_name
}

# ── SIEM Stack ────────────────────────────────────────────────────────────────
output "elas_private_ips" {
  value = module.elas.internal_ips
}


output "logstash_private" {
  value = module.logstash.internal_ips
}

output "logstash_public" {
  value = module.logstash.external_ips
}

output "bastion_public_ip" {
  value = module.bastion.external_ips
}

# --- App private ip --------------------------------------
output "app1_private_ip" {
  value = module.app1.internal_ips
}

output "app2_private_ip" {
  value = module.app2.internal_ips
}

# ── Security Groups ───────────────────────────────────────────────────────────
output "sg_alb_id" {
  value = module.security_groups.sg_alb_id
}

output "sg_bastion_id" {
  value = module.security_groups.sg_bastion_id
}

output "sg_nlb_id" {
  value = module.security_groups.sg_nlb_id
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

output "sg_db_id" {
  value = module.security_groups.sg_db_id
}

# ── App / Dev User Data ───────────────────────────────────────────────────────
output "ecr_urls" {
  description = "ECR repository URLs per app – set in GitLab CI/CD variables"
  value       = module.iam_users.ecr_urls
}

output "app_sg_ids" {
  description = "Security Group ID per app"
  value       = module.iam_users.app_sg_ids
}

output "user_app_mapping" {
  description = "Mapping: user → allowed apps"
  value       = module.iam_users.user_app_mapping
}

output "user_credentials" {
  description = "Access keys per dev user (sensitive) – run: terraform output -json user_credentials"
  value       = module.iam_users.user_credentials
  sensitive   = true
}
