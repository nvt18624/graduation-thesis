output "alb_dns_name" {
  description = "ALB DNS name – dùng làm endpoint cho app và Kibana (/kibana*)"
  value       = aws_lb.alb.dns_name
}

output "alb_arn" {
  value = aws_lb.alb.arn
}

output "tg_app_arn" {
  value = aws_lb_target_group.tg_app.arn
}

output "tg_kibana_arn" {
  value = aws_lb_target_group.tg_kibana.arn
}
