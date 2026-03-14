output "user_credentials" {
  description = <<-EOT
    Access keys for each dev – admin copy and set to GitLab CI/CD Variables:
      AWS_ACCESS_KEY_ID     = <access_key_id>
      AWS_SECRET_ACCESS_KEY = <secret>
    Then dev only need to addly set:
      AWS_REGION   = ap-southeast-1
      ECR_REPO_URL = <ecr url của app họ>
  EOT
  sensitive = true
  value = {
    for user, key in aws_iam_access_key.devs : user => {
      access_key_id     = key.id
      secret_access_key = key.secret
      allowed_apps      = var.users[user].allowed_apps
    }
  }
}

# Non-sensitive: ECR URLs for each app
output "ecr_urls" {
  description = "ECR repository URL theo từng app"
  value = {
    for app, repo in aws_ecr_repository.apps : app => repo.repository_url
  }
}

# Security Group IDs with app
output "app_sg_ids" {
  description = "Security Group ID theo từng app"
  value = {
    for app, sg in aws_security_group.apps : app => sg.id
  }
}

# Summary for admin to know what key  → user  → app 
output "user_app_mapping" {
  description = "Mapping user → apps được phép (không sensitive)"
  value = {
    for user, cfg in var.users : user => {
      allowed_apps = cfg.allowed_apps
      ecr_repos = [
        for app in cfg.allowed_apps : aws_ecr_repository.apps[app].repository_url
      ]
    }
  }
}
