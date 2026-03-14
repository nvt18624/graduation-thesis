variable "prefix" {
  description = "Prefix name as resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for create Security Groups for apps"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR for ingress rule in SG"
  type        = string
}

variable "apps" {
  description = <<-EOT
    Map applications need deploy.
    example:
      apps = {
        app1 = { app_port = 8080 }
        app2 = { app_port = 3000 }
      }
  EOT
  type = map(object({
    app_port = number
  }))
}

variable "users" {
  description = <<-EOT
    Map dev users and apps that they are allowed to deploy.
    example:
      users = {
        dev1 = { allowed_apps = ["app1"] }
        dev2 = { allowed_apps = ["app2"] }
        dev3 = { allowed_apps = ["app1", "app2"] }
      }
  EOT
  type = map(object({
    allowed_apps = list(string)
  }))

  validation {
    condition = alltrue([
      for user, cfg in var.users :
      length(cfg.allowed_apps) > 0
    ])
    error_message = "Each user have 1 allowed_apps."
  }
}
