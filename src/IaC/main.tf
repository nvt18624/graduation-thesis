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

//// Monitoring cluster

//elastich 
module "elas" {
  source           = "./modules/instance"
  instance_name    = "elas"
  machine_type     = "m7i-flex.large"
  ami_id           = "ami-00d8fc944fb171e29"
  subnetwork       = module.network.subnet_2
  security_groups  = [module.firewall-1.default_sg_id]
  key_name         = "my-aws-key"
  enable_public_ip = true
  internal_ip       = ["10.0.1.10"]
}

// kibana
module "kibana" {
  source           = "./modules/instance"
  instance_name    = "kibana"
  machine_type     = "m7i-flex.large"
  ami_id           = "ami-00d8fc944fb171e29"
  subnetwork       = module.network.subnet_2
  security_groups  = [module.firewall-1.default_sg_id]
  key_name         = "my-aws-key"
  enable_public_ip = true
  internal_ip       = ["10.0.1.11"]
}

//elastich
module "logstash" {
  source           = "./modules/instance"
  instance_name    = "logstash"
  machine_type     = "m7i-flex.large"
  ami_id           = "ami-00d8fc944fb171e29"
  subnetwork       = module.network.subnet_2
  security_groups  = [module.firewall-1.default_sg_id]
  key_name         = "my-aws-key"
  enable_public_ip = true
  internal_ip       = ["10.0.1.12"]
}
