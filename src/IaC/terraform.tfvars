# ── Network ───────────────────────────────────────────────────────────────────
network_name = "network_aws"
vpc_cidr     = "10.0.0.0/16"

public_subnet_cidr   = "10.0.1.0/24"   # ALB, Bastion, NLB, NAT Gateway
public_subnet_az     = "ap-southeast-1a"
public_subnet_2_cidr = "10.0.6.0/24"   # ALB HA – 2nd AZ required by AWS ALB
public_subnet_2_az   = "ap-southeast-1b"

private_app_subnet_cidr  = "10.0.2.0/24"   # App EC2 (created/destroyed per dev request)
private_app_subnet_az    = "ap-southeast-1a"
private_siem_subnet_cidr = "10.0.3.0/24"   # Elasticsearch, Kibana, Logstash
private_siem_subnet_az   = "ap-southeast-1a"
private_data_subnet_cidr = "10.0.4.0/24"   # DB + S3/ECR via VPC endpoints (no internet)
private_data_subnet_az   = "ap-southeast-1a"

# ── Security ──────────────────────────────────────────────────────────────────
# Replace with your actual admin IP (e.g. "203.0.113.10/32")
admin_cidr_blocks = ["171.241.57.160/32"]

# Replace with your on-premise network CIDR(s) that ship logs
onpremise_cidr_blocks = ["118.70.57.134/32"]

# ── Load Balancers ────────────────────────────────────────────────────────────
# ── IAM / S3 ─────────────────────────────────────────────────────────────────
log_s3_bucket_arns = []

# ── Apps (each gets 1 ECR repo + security group) ─────────────────────────────
apps = {
  app1 = { app_port = 8080 }
  app2 = { app_port = 3000 }
}

# ── Dev users (least privilege – can only deploy to assigned apps) ────────────
dev_users = {
  dev1 = { allowed_apps = ["app1"] }
  dev2 = { allowed_apps = ["app2"] }
  # dev3 = { allowed_apps = ["app1", "app2"] }
}
