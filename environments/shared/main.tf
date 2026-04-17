terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "shopflow-terraform-state-122610497964"
    key    = "shared/terraform.tfstate"
    region = "eu-west-1"
  }
}

provider "aws" {
  region = var.aws_region
}

# =============================================================
# Shared VPC — used by ALL 3 EKS clusters
# =============================================================
# Single VPC with 6 private subnets (2 per cluster) + 2 public
# CIDR: 10.0.0.0/16
#   Public:  10.0.0.0/24, 10.0.1.0/24
#   Private: 10.0.10.0/24 - 10.0.15.0/24 (for 3 clusters)
# =============================================================

resource "aws_vpc" "shared" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-shared-vpc"
    Environment = "shared"
    Project     = var.project_name
    # Tag for all 3 clusters
    "kubernetes.io/cluster/${var.project_name}-workload"      = "shared"
    "kubernetes.io/cluster/${var.project_name}-platform"      = "shared"
    "kubernetes.io/cluster/${var.project_name}-observability"  = "shared"
  }
}

# ---------- Public Subnets (shared by all clusters for LBs) ----------

resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.shared.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.project_name}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/role/elb" = "1"
  }
}

# ---------- Private Subnets — 2 per cluster ----------

resource "aws_subnet" "workload" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.shared.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 10 + count.index)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                                                       = "${var.project_name}-workload-${var.availability_zones[count.index]}"
    "kubernetes.io/cluster/${var.project_name}-workload"       = "shared"
    "kubernetes.io/role/internal-elb"                           = "1"
  }
}

resource "aws_subnet" "platform" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.shared.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 12 + count.index)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                                                       = "${var.project_name}-platform-${var.availability_zones[count.index]}"
    "kubernetes.io/cluster/${var.project_name}-platform"       = "shared"
    "kubernetes.io/role/internal-elb"                           = "1"
  }
}

resource "aws_subnet" "observability" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.shared.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 14 + count.index)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                                                           = "${var.project_name}-observability-${var.availability_zones[count.index]}"
    "kubernetes.io/cluster/${var.project_name}-observability"     = "shared"
    "kubernetes.io/role/internal-elb"                               = "1"
  }
}

# ---------- Internet Gateway ----------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.shared.id
  tags   = { Name = "${var.project_name}-igw" }
}

# ---------- NAT Gateway ----------

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project_name}-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.project_name}-nat-gw" }
  depends_on    = [aws_internet_gateway.main]
}

# ---------- Route Tables ----------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.shared.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.shared.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = { Name = "${var.project_name}-private-rt" }
}

# Associate public subnets
resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Associate ALL private subnets (workload + platform + observability)
resource "aws_route_table_association" "workload" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.workload[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "platform" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.platform[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "observability" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.observability[count.index].id
  route_table_id = aws_route_table.private.id
}

# =============================================================
# ECR — shared container registry
# =============================================================

module "ecr" {
  source       = "../../modules/ecr"
  project_name = var.project_name
  tags         = { Project = var.project_name, Environment = "shared" }
}
