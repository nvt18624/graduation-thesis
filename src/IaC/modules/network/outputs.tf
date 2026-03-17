output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "internet_gateway_id" {
  value = aws_internet_gateway.igw.id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.nat_gw.id
}

# ── Public Subnets ────────────────────────────────────────────────────────────
output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "public_subnet_2_id" {
  value = aws_subnet.public_2.id
}

output "public_subnet_ids" {
  description = "Both public subnet IDs – used by ALB (requires 2 AZs)"
  value       = [aws_subnet.public.id, aws_subnet.public_2.id]
}

output "public_route_table_id" {
  value = aws_route_table.public_rt.id
}

# ── Private Subnets ───────────────────────────────────────────────────────────
output "private_app_subnet_id" {
  value = aws_subnet.private_app.id
}

output "private_siem_subnet_id" {
  value = aws_subnet.private_siem.id
}

output "private_data_subnet_id" {
  value = aws_subnet.private_data.id
}

# ── VPC Endpoints ─────────────────────────────────────────────────────────────
output "s3_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}

output "ecr_api_endpoint_id" {
  value = aws_vpc_endpoint.ecr_api.id
}

output "ecr_dkr_endpoint_id" {
  value = aws_vpc_endpoint.ecr_dkr.id
}

# ── Legacy outputs (backward compatibility) ───────────────────────────────────
output "network_name" {
  value = aws_vpc.vpc.id
}

output "subnet_2" {
  value = aws_subnet.public.id
}

output "subnetwork_id_2" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Alias → private_app_subnet_id"
  value       = aws_subnet.private_app.id
}
