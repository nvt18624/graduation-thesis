resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.network_name }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = { Name = "${var.network_name}-igw" }
}

# ── Public Subnet 1 (10.0.1.0/24, az-1a) – ALB, Bastion, NLB, NAT ───────────
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.public_subnet_az
  map_public_ip_on_launch = true

  tags = { Name = "${var.network_name}-public", Tier = "public" }
}

# ── Public Subnet 2 (10.0.6.0/24, az-1b) – ALB HA (AWS requires ≥ 2 AZs) ───
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = var.public_subnet_2_az
  map_public_ip_on_launch = true

  tags = { Name = "${var.network_name}-public-2", Tier = "public" }
}

# ── Private App Subnet (10.0.2.0/24) – App EC2 instances ─────────────────────
resource "aws_subnet" "private_app" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.private_app_subnet_cidr
  availability_zone = var.private_app_subnet_az

  tags = { Name = "${var.network_name}-private-app", Tier = "private-app" }
}

# ── Private SIEM Subnet (10.0.3.0/24) – Elasticsearch, Kibana, Logstash ──────
resource "aws_subnet" "private_siem" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.private_siem_subnet_cidr
  availability_zone = var.private_siem_subnet_az

  tags = { Name = "${var.network_name}-private-siem", Tier = "private-siem" }
}

# ── Private Data Subnet (10.0.4.0/24) – DB + S3/ECR via VPC endpoints only ───
resource "aws_subnet" "private_data" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.private_data_subnet_cidr
  availability_zone = var.private_data_subnet_az

  tags = { Name = "${var.network_name}-private-data", Tier = "private-data" }
}

# ── NAT Gateway in Public Subnet 1 ───────────────────────────────────────────
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = { Name = "${var.network_name}-nat-eip" }
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id

  tags = { Name = "${var.network_name}-nat-gw" }

  depends_on = [aws_internet_gateway.igw]
}

# ── Public Route Table (→ IGW) ────────────────────────────────────────────────
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.network_name}-public-rt" }
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_2_rta" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}

# ── Private App Route Table (→ NAT Gateway) ───────────────────────────────────
resource "aws_route_table" "private_app_rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = { Name = "${var.network_name}-private-app-rt" }
}

resource "aws_route_table_association" "private_app_rta" {
  subnet_id      = aws_subnet.private_app.id
  route_table_id = aws_route_table.private_app_rt.id
}

# ── Private SIEM Route Table (→ NAT Gateway) ──────────────────────────────────
resource "aws_route_table" "private_siem_rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = { Name = "${var.network_name}-private-siem-rt" }
}

resource "aws_route_table_association" "private_siem_rta" {
  subnet_id      = aws_subnet.private_siem.id
  route_table_id = aws_route_table.private_siem_rt.id
}

# ── Private Data Route Table (NO internet – VPC endpoints only) ───────────────
resource "aws_route_table" "private_data_rt" {
  vpc_id = aws_vpc.vpc.id

  # Intentionally no 0.0.0.0/0 route – completely isolated from internet

  tags = { Name = "${var.network_name}-private-data-rt" }
}

resource "aws_route_table_association" "private_data_rta" {
  subnet_id      = aws_subnet.private_data.id
  route_table_id = aws_route_table.private_data_rt.id
}

# ── VPC Endpoint: S3 Gateway (free, attaches to data route table) ─────────────
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_data_rt.id]

  tags = { Name = "${var.network_name}-s3-endpoint" }
}

# ── SG for Interface VPC Endpoints (allow HTTPS from within VPC only) ─────────
resource "aws_security_group" "sg_vpc_endpoint" {
  name        = "${var.network_name}-sg-vpc-endpoint"
  description = "Allow HTTPS 443 from VPC CIDR to interface endpoints"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.network_name}-sg-vpc-endpoint" }
}

# ── VPC Endpoint: ECR API (Interface) ─────────────────────────────────────────
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.vpc.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_data.id]
  security_group_ids  = [aws_security_group.sg_vpc_endpoint.id]
  private_dns_enabled = true

  tags = { Name = "${var.network_name}-ecr-api-endpoint" }
}

# ── VPC Endpoint: ECR DKR (Interface) ─────────────────────────────────────────
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.vpc.id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_data.id]
  security_group_ids  = [aws_security_group.sg_vpc_endpoint.id]
  private_dns_enabled = true

  tags = { Name = "${var.network_name}-ecr-dkr-endpoint" }
}
