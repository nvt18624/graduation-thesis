# ── Network: VPC, subnets, IGW, NAT, route tables, VPC endpoints ──────────────
module "network" {
  source                   = "./modules/network/"
  vpc_cidr                 = var.vpc_cidr
  network_name             = var.network_name
  region                   = var.region
  public_subnet_cidr       = var.public_subnet_cidr
  public_subnet_az         = var.public_subnet_az
  public_subnet_2_cidr     = var.public_subnet_2_cidr
  public_subnet_2_az       = var.public_subnet_2_az
  private_app_subnet_cidr  = var.private_app_subnet_cidr
  private_app_subnet_az    = var.private_app_subnet_az
  private_siem_subnet_cidr = var.private_siem_subnet_cidr
  private_siem_subnet_az   = var.private_siem_subnet_az
  private_data_subnet_cidr = var.private_data_subnet_cidr
  private_data_subnet_az   = var.private_data_subnet_az
}

# ── IAM Users + ECR repos + App SGs (least privilege per dev) ─────────────────
# Created before security_groups so app SG IDs can be passed to DB SG
module "iam_users" {
  source   = "./modules/iam_users/"
  prefix   = var.network_name
  vpc_id   = module.network.vpc_id
  vpc_cidr = var.vpc_cidr
  apps     = var.apps
  users    = var.dev_users
}

# ── Security Groups (ALB, Bastion, NLB, ELK, DB) ──────────────────────────────
module "security_groups" {
  source                = "./modules/security_groups/"
  prefix                = var.network_name
  vpc_id                = module.network.vpc_id
  vpc_cidr              = var.vpc_cidr
  admin_cidr_blocks     = var.admin_cidr_blocks
  onpremise_cidr_blocks = var.onpremise_cidr_blocks
  app_sg_ids            = values(module.iam_users.app_sg_ids)
}

# ── IAM Roles + Instance Profiles for ELK stack ───────────────────────────────
module "iam" {
  source             = "./modules/iam/"
  prefix             = var.network_name
  log_s3_bucket_arns = var.log_s3_bucket_arns
}

# ── Load Balancers: 3 ALBs (HTTPS 443) + 1 NLB (5044, 8080) ──────────────────
module "load_balancers" {
  source             = "./modules/load_balancers/"
  prefix             = var.network_name
  vpc_id             = module.network.vpc_id
  alb_sg_id          = module.security_groups.sg_alb_id
  public_subnet_ids  = module.network.public_subnet_ids
  kibana_instance_id = module.kibana.instance_ids[0]
}

# ── Bastion Host (public subnet, SSH jump to private instances) ────────────────
module "bastion" {
  source           = "./modules/instance"
  instance_name    = "bastion"
  machine_type     = "t3.micro"
  ami_id           = var.ami_id
  subnetwork       = module.network.public_subnet_id
  security_groups  = [module.security_groups.sg_bastion_id]
  key_name         = var.key_name
  enable_public_ip = true
  internal_ip      = ["10.0.1.10"]
}

//// SIEM Stack (Elasticsearch, Kibana, Logstash) – private SIEM subnet 10.0.3.0/24

# Elasticsearch – private SIEM subnet, no public IP
module "elas" {
  source               = "./modules/instance"
  instance_name        = "elas"
  machine_type         = "t3.micro"
  ami_id               = var.ami_id
  subnetwork           = module.network.private_siem_subnet_id
  security_groups      = [module.security_groups.sg_elasticsearch_id]
  key_name             = var.key_name
  enable_public_ip     = false
  internal_ip          = ["10.0.3.10"]
  iam_instance_profile = module.iam.elasticsearch_instance_profile
}

# Kibana – private SIEM subnet, access via ALB-2 only
module "kibana" {
  source               = "./modules/instance"
  instance_name        = "kibana"
  machine_type         = "t3.micro"
  ami_id               = var.ami_id
  subnetwork           = module.network.private_siem_subnet_id
  security_groups      = [module.security_groups.sg_kibana_id]
  key_name             = var.key_name
  enable_public_ip     = false
  internal_ip          = ["10.0.3.11"]
  iam_instance_profile = module.iam.kibana_instance_profile
}

# Logstash – public subnet, internet-facing that receive log from on-premise
module "logstash" {
  source               = "./modules/instance"
  instance_name        = "logstash"
  machine_type         = "t3.micro"
  ami_id               = var.ami_id
  subnetwork           = module.network.public_subnet_id
  security_groups      = [module.security_groups.sg_logstash_id]
  key_name             = var.key_name
  enable_public_ip     = true
  internal_ip          = ["10.0.1.12"]
  iam_instance_profile = module.iam.logstash_instance_profile
}

# ── Copy scripts to VMs  ─────────────────────────────────────────

resource "null_resource" "copy_elas_script" {
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("/home/tn18624/.ssh/id_rsa")
    host        = module.elas.internal_ips[0]

    bastion_host        = module.bastion.external_ips[0]
    bastion_user        = "ubuntu"
    bastion_private_key = file("/home/tn18624/.ssh/id_rsa")
  }

  provisioner "file" {
    source      = "scripts/elas.sh"
    destination = "/home/ubuntu/elas.sh"
  }

  depends_on = [module.elas, module.bastion]
}

resource "null_resource" "copy_kibana_script" {
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("/home/tn18624/.ssh/id_rsa")
    host        = module.kibana.internal_ips[0]

    bastion_host        = module.bastion.external_ips[0]
    bastion_user        = "ubuntu"
    bastion_private_key = file("/home/tn18624/.ssh/id_rsa")
  }

  provisioner "file" {
    source      = "scripts/kibana.sh"
    destination = "/home/ubuntu/kibana.sh"
  }

  depends_on = [module.kibana, module.bastion]
}

resource "null_resource" "copy_logstash_script" {
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("/home/tn18624/.ssh/id_rsa")
    host        = module.logstash.internal_ips[0]

    bastion_host        = module.bastion.external_ips[0]
    bastion_user        = "ubuntu"
    bastion_private_key = file("/home/tn18624/.ssh/id_rsa")
  }

  provisioner "file" {
    source      = "scripts/logstash.sh"
    destination = "/home/ubuntu/logstash.sh"
  }

  depends_on = [module.logstash, module.bastion]
}

//// Private App subnet (10.0.2.0/24) – app EC2s are created/destroyed on demand
//// by dev users via iam_users module permissions (ECR push + SSM deploy).
//// No static instances defined here; use module "instance" ad-hoc per app.

# module "database" {
#   source           = "./modules/instance"
#   instance_name    = "database"
#   machine_type     = "t3.micro"
#   ami_id           = var.ami_id
#   subnetwork       = module.network.private_data_subnet_id
#   security_groups  = [module.security_groups.sg_db_id]
#   key_name         = var.key_name
#   enable_public_ip = false
#   internal_ip      = ["10.0.4.10"]
# }
