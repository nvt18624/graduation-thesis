module "network" {
  source              = "./modules/network/"
  vpc_cidr            = var.vpc_cidr
  network_name        = var.network_name
  subnet_2_name       = var.subnet_2_name
  subnet_2_range      = var.subnet_2_range
  subnet_2_az         = var.subnet_2_az
  private_subnet_cidr = var.private_subnet_cidr
  private_subnet_az   = var.private_subnet_az
}

# Micro-segmented Security Groups (each service have 1 SG)
module "security_groups" {
  source            = "./modules/security_groups/"
  prefix            = var.network_name
  vpc_id            = module.network.vpc_id
  admin_cidr_blocks = var.admin_cidr_blocks
}

# IAM Roles + Instance Profiles (least privilege)
module "iam" {
  source             = "./modules/iam/"
  prefix             = var.network_name
  log_s3_bucket_arns = var.log_s3_bucket_arns
}

# IAM Users + Access Keys + Security Groups per app (least privilege per dev)
module "iam_users" {
  source   = "./modules/iam_users/"
  prefix   = var.network_name
  vpc_id   = module.network.vpc_id
  vpc_cidr = var.vpc_cidr
  apps     = var.apps
  users    = var.dev_users
}

//// Monitoring cluster (ELK Stack)

# Elasticsearch – private subnet, no public IP
module "elas" {
  source               = "./modules/instance"
  instance_name        = "elas"
  machine_type         = "m7i-flex.large"
  ami_id               = "ami-00d8fc944fb171e29"
  subnetwork           = module.network.private_subnet_id
  security_groups      = [module.security_groups.sg_elasticsearch_id]
  key_name             = "my-aws-key"
  enable_public_ip     = false
  internal_ip          = ["10.0.2.10"]
  iam_instance_profile = module.iam.elasticsearch_instance_profile
}

# Kibana – public subnet, only open port 5601
module "kibana" {
  source               = "./modules/instance"
  instance_name        = "kibana"
  machine_type         = "m7i-flex.large"
  ami_id               = "ami-00d8fc944fb171e29"
  subnetwork           = module.network.subnet_2
  security_groups      = [module.security_groups.sg_kibana_id]
  key_name             = "my-aws-key"
  enable_public_ip     = true
  internal_ip          = ["10.0.1.11"]
  iam_instance_profile = module.iam.kibana_instance_profile
}

# Logstash – public subnet, open 5044 + 8080
module "logstash" {
  source               = "./modules/instance"
  instance_name        = "logstash"
  machine_type         = "m7i-flex.large"
  ami_id               = "ami-00d8fc944fb171e29"
  subnetwork           = module.network.subnet_2
  security_groups      = [module.security_groups.sg_logstash_id]
  key_name             = "my-aws-key"
  enable_public_ip     = true
  internal_ip          = ["10.0.1.12"]
  iam_instance_profile = module.iam.logstash_instance_profile
}
