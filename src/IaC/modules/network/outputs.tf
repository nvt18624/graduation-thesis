output "subnet_2" {
  value = aws_subnet.subnet_2.id
}
output "network_name" {
  value = aws_vpc.vpc.id
}
output "subnetwork_id_2" {
  value = aws_subnet.subnet_2.id
}
output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "internet_gateway_id" {
  value = aws_internet_gateway.igw.id
}

output "public_route_table_id" {
  value = aws_route_table.public_rt.id
}
