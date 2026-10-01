# 1. Create the VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  lifecycle {
    precondition {
      condition     = length(data.aws_availability_zones.available.names) >= 2
      error_message = "The selected AWS region must have at least 2 available Availability Zones."
    }
  }

  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  }
}

# 2. Create Internet Gateway for Public Subnets
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.environment}-igw"
    Environment = var.environment
  }
}

# 3. Create Public Subnets (Iterates over public_subnet_cidrs)
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.environment}-public-subnet-${count.index + 1}"
    Environment = var.environment
  }
}

# 4. Create Private Subnets
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name        = "${var.environment}-private-subnet-${count.index + 1}"
    Environment = var.environment
  }
}

# 5. Public Route Table (Directs outbound traffic to the Internet Gateway)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name        = "${var.environment}-public-rt"
    Environment = var.environment
  }
}

# 6. Associate Route Table with Public Subnets
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Fetch your current public IP dynamically
data "http" "my_public_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  # Clean up the IP address string and format as CIDR (/32)
  my_ip = "${chomp(data.http.my_public_ip.response_body)}/32"
}


resource "aws_security_group" "bastion_sg" {
  name        = "${var.environment}-bastion-sg"
  description = "Allow SSH access from my current public IP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from my workstation"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-bastion-sg"
    Environment = var.environment
  }
}

# 1. Create Elastic IPs (EIP) required for NAT Gateways
resource "aws_eip" "nat" {
  count  = var.environment == "prod" ? length(data.aws_availability_zones.available.names) : 1
  domain = "vpc"

  tags = {
    Name        = "${var.environment}-eip-${count.index + 1}"
    Environment = var.environment
  }
}

# 2. Create NAT Gateways based on environment
resource "aws_nat_gateway" "nat" {
  count         = var.environment == "prod" ? length(data.aws_availability_zones.available.names) : 1
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name        = "${var.environment}-nat-${count.index + 1}"
    Environment = var.environment
  }
}
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Dynamically calculates /24 subnets for every available AZ
  # Example output: ["10.0.1.0/24", "10.0.2.0/24", ...]
  public_subnet_cidrs = [
    for i in range(length(data.aws_availability_zones.available.names)) :
    cidrsubnet(var.vpc_cidr, 8, i + 1)
  ]

  private_subnet_cidrs = [
    for i in range(length(data.aws_availability_zones.available.names)) :
    cidrsubnet(var.vpc_cidr, 8, i + 10)
  ]
}