// network
network_name        = "network_aws"
subnet_2_name       = "subnet_2_aws"
subnet_2_range      = "10.0.0.0/16"
subnet_2_az         = "ap-southeast-1a"
vpc_cidr            = "10.0.0.0/16"
private_subnet_cidr = "10.0.2.0/24"
private_subnet_az   = "ap-southeast-1a"

admin_cidr_blocks = ["0.0.0.0/0"]

log_s3_bucket_arns = []

// List apps (Each app have 1 ECR repo + SG)
apps = {
  app1 = { app_port = 8080 }
  app2 = { app_port = 3000 }
}

dev_users = {
  dev1 = { allowed_apps = ["app1"] }
  dev2 = { allowed_apps = ["app2"] }
  # dev3 = { allowed_apps = ["app1", "app2"] } 
}
