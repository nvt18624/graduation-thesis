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
