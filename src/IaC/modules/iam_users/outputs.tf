output "user_credentials" {
  description = <<-EOT
    Access keys for each dev – admin copy and set to GitLab CI/CD Variables:
      AWS_ACCESS_KEY_ID     = <access_key_id>
      AWS_SECRET_ACCESS_KEY = <secret>
    Then dev only need to addly set:
      AWS_REGION   = ap-southeast-1
      ECR_REPO_URL = <ecr url của app họ>
  EOT
  sensitive   = true
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

output "app_instance_profile" {
  description = "IAM instance profile name to attach to app EC2 instances"
  value       = aws_iam_instance_profile.app_ec2.name
}

output "rollback_lambda_arn" {
  description = "ARN of the AI rollback Lambda – pass to AI system to invoke"
  value       = aws_lambda_function.rollback.arn
}

output "ai_rollback_policy_arn" {
  description = "IAM policy ARN granting lambda:InvokeFunction on the rollback Lambda – attach to AI system's IAM role/user"
  value       = aws_iam_policy.ai_rollback_invoke.arn
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
