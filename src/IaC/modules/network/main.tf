resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.network_name
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.network_name}-igw"
  }
}

resource "aws_subnet" "subnet_2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.public_subnet_az
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.network_name}-public-subnet"
    Tier = "public"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.network_name}-public-rt"
  }
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

