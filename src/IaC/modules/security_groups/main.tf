# ── ALB SG (internet → 80 only) ──────────────────────────────────────────────
resource "aws_security_group" "sg_alb" {
  name        = "${var.prefix}-sg-alb"
  description = "ALB: accept HTTP from internet only"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = toset(var.app_ports)
    content {
      description = "App port ${ingress.value} from internet"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-sg-alb" }
}

# ── Bastion SG (fixed admin IP → 22 only) ─────────────────────────────────────
resource "aws_security_group" "sg_bastion" {
  name        = "${var.prefix}-sg-bastion"
  description = "Bastion: SSH only from trusted admin CIDR"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-sg-bastion" }
}

# ── NLB SG (on-premise IP → 5044, 8080 only) ──────────────────────────────────
resource "aws_security_group" "sg_nlb" {
  name        = "${var.prefix}-sg-nlb"
  description = "NLB: log ingestion from on-premise network only"
  vpc_id      = var.vpc_id

  ingress {
    description = "Beats/Logstash input from on-premise"
    from_port   = 5044
    to_port     = 5044
    protocol    = "tcp"
    cidr_blocks = var.onpremise_cidr_blocks
  }

  ingress {
    description = "HTTP log input from on-premise"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.onpremise_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-sg-nlb" }
}

# ── Elasticsearch SG (VPC CIDR → 9200, Kibana+Logstash → 9300, Bastion → 22) ─
resource "aws_security_group" "sg_elasticsearch" {
  name        = "${var.prefix}-sg-elasticsearch"
  description = "Elasticsearch: REST API from VPC, cluster transport from ELK SGs"
  vpc_id      = var.vpc_id

  ingress {
    description = "ES REST API from anywhere in VPC"
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description     = "ES cluster transport from Kibana + Logstash"
    from_port       = 9300
    to_port         = 9300
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_kibana.id, aws_security_group.sg_logstash.id]
  }

  ingress {
    description     = "SSH via bastion only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-sg-elasticsearch" }
}

# ── Kibana SG (ALB → 5601, Bastion → 22) ──────────────────────────────────────
resource "aws_security_group" "sg_kibana" {
  name        = "${var.prefix}-sg-kibana"
  description = "Kibana: UI only from ALB, SSH via bastion"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Kibana UI from ALB"
    from_port       = 5601
    to_port         = 5601
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_alb.id]
  }

  ingress {
    description     = "SSH via bastion only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-sg-kibana" }
}

# ── Logstash SG (VPC CIDR → 5044/8080, Bastion → 22) ─────────────────────────
resource "aws_security_group" "sg_logstash" {
  name        = "${var.prefix}-sg-logstash"
  description = "Logstash: log ports from VPC (NLB forwards on-premise), SSH via bastion"
  vpc_id      = var.vpc_id

  ingress {
    description = "Beats input from VPC (NLB proxies on-premise traffic)"
    from_port   = 5044
    to_port     = 5044
    protocol    = "tcp"
    cidr_blocks = concat([var.vpc_cidr], var.onpremise_cidr_blocks)
  }

  ingress {
    description = "HTTP log input from VPC"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = concat([var.vpc_cidr], var.onpremise_cidr_blocks)
  }

  ingress {
    description     = "SSH via bastion only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks = concat([var.vpc_cidr], var.onpremise_cidr_blocks)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-sg-logstash" }
}

# ── DB SG (app SGs → 5432, Bastion → 22) ─────────────────────────────────────
resource "aws_security_group" "sg_db" {
  name        = "${var.prefix}-sg-db"
  description = "DB: PostgreSQL from app instances only, SSH via bastion"
  vpc_id      = var.vpc_id

  # Only create the PostgreSQL ingress rule if app SGs exist (avoids empty list error)
  dynamic "ingress" {
    for_each = length(var.app_sg_ids) > 0 ? [1] : []
    content {
      description     = "PostgreSQL from app instances"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = var.app_sg_ids
    }
  }

  ingress {
    description     = "SSH via bastion only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-sg-db" }
}
