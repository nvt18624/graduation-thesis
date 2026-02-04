module "network" {
  source = "./modules/network/"
  vpc_cidr = var.vpc_cidr
  network_name = var.network_name
  subnet_2_name = var.subnet_2_name
  subnet_2_range = var.subnet_2_range
  # subnet_2_az =ar.subnet_2_az
}

//firewall 
module "firewall-1" {
  source        = "./modules/firewall/"
  firewall_name = "port-service"
  vpc_id        = module.network.vpc_id      
  protocol      = "tcp"
  ports         = var.ports
  source_ranges = var.source_ranges
}
