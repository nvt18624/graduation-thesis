locals {
  name = replace(var.prefix, "_", "-")
}

# ── 1 Application Load Balancer (HTTP 80) ─────────────────────────────────────
resource "aws_lb" "alb" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  tags = { Name = "${local.name}-alb" }
}

# ── Target Group: App (port 8080, default) ────────────────────────────────────
resource "aws_lb_target_group" "tg_app" {
  name        = "${local.name}-tg-app"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = { Name = "${local.name}-tg-app" }
}

# ── Target Group: Kibana (port 5601) ──────────────────────────────────────────
resource "aws_lb_target_group" "tg_kibana" {
  name        = "${local.name}-tg-kibana"
  port        = 5601
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/api/status"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = { Name = "${local.name}-tg-kibana" }
}

# ── HTTP Listener port 80 ─────────────────────────────────────────────────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  # Default → App
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_app.arn
  }
}

# ── Listener rule: /kibana* → Kibana target group ─────────────────────────────
resource "aws_lb_listener_rule" "kibana" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_kibana.arn
  }

  condition {
    path_pattern {
      values = ["/kibana", "/kibana/*"]
    }
  }
}

# ── Register Kibana instance ───────────────────────────────────────────────────
resource "aws_lb_target_group_attachment" "kibana" {
  target_group_arn = aws_lb_target_group.tg_kibana.arn
  target_id        = var.kibana_instance_id
  port             = 5601
}

# ── Target Groups: 1 per app (dynamic) ───────────────────────────────────────
resource "aws_lb_target_group" "apps" {
  for_each = var.app_ports

  name        = "${local.name}-tg-${each.key}"
  port        = each.value
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = { Name = "${local.name}-tg-${each.key}", App = each.key }
}

# ── Listeners: 1 per app port (internet → ALB:PORT) ──────────────────────────
resource "aws_lb_listener" "apps" {
  for_each = var.app_ports

  load_balancer_arn = aws_lb.alb.arn
  port              = each.value
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.apps[each.key].arn
  }
}

# ── Register app instances to their target groups ────────────────────────────
resource "aws_lb_target_group_attachment" "apps" {
  for_each = var.app_instances

  target_group_arn = aws_lb_target_group.apps[each.key].arn
  target_id        = each.value
  port             = var.app_ports[each.key]
}
