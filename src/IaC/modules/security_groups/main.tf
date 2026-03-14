resource "aws_security_group" "sg_elasticsearch" {
  name        = "${var.prefix}-sg-elasticsearch"
  description = "Elasticsearch: only allow traffic from Kibana and Logstash SGs"
  vpc_id      = var.vpc_id

  ingress {
    description     = "ES REST API from Kibana"
    from_port       = 9200
    to_port         = 9200
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_kibana.id]
  }

  ingress {
    description     = "ES REST API from Logstash"
    from_port       = 9200
    to_port         = 9200
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_logstash.id]
  }

  ingress {
    description     = "ES cluster transport from Kibana + Logstash"
    from_port       = 9300
    to_port         = 9300
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_kibana.id, aws_security_group.sg_logstash.id]
  }

  ingress {
    description = "SSH from admin CIDR"
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

  tags = { Name = "${var.prefix}-sg-elasticsearch" }
}

# ── Kibana SG (public – UI access) ───────────────────────────────────────────
resource "aws_security_group" "sg_kibana" {
  name        = "${var.prefix}-sg-kibana"
  description = "Kibana: allow web UI from internet, SSH from admin"
  vpc_id      = var.vpc_id

  ingress {
    description = "Kibana UI"
    from_port   = 5601
    to_port     = 5601
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from admin CIDR"
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

  tags = { Name = "${var.prefix}-sg-kibana" }
}

# ── Logstash SG (public –  logs from apps) ─────────────────────────────────
resource "aws_security_group" "sg_logstash" {
  name        = "${var.prefix}-sg-logstash"
  description = "Logstash: receive logs from apps, SSH from admin"
  vpc_id      = var.vpc_id

  ingress {
    description = "Beats/Logstash input"
    from_port   = 5044
    to_port     = 5044
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP input"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from admin CIDR"
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

  tags = { Name = "${var.prefix}-sg-logstash" }
}
