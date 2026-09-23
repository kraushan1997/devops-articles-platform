data "aws_availability_zones" "available" {
  state = "available"

  # skip Local Zones / Wavelength zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Tags that EKS, the AWS Load Balancer Controller and Karpenter use to find subnets
  cluster_tag = { "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared" }
}

# create vpc

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.eks_cluster_name}-vpc"
  }
}

# create public subnets (one per AZ) - internet-facing ALBs and the NAT gateways live here
# 10.0.0.0/24, 10.0.1.0/24, 10.0.2.0/24

resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.cluster_tag, {
    Name                     = "${var.eks_cluster_name}-public-${local.azs[count.index]}"
    "kubernetes.io/role/elb" = "1" # internet-facing load balancers
  })
}

# create private subnets (one per AZ) - nodes and pods live here
# /20 each (4091 IPs): with the VPC CNI every pod gets a VPC IP, so /24 runs out fast
# 10.0.16.0/20, 10.0.32.0/20, 10.0.48.0/20

resource "aws_subnet" "private" {
  count             = var.az_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 1)
  availability_zone = local.azs[count.index]

  tags = merge(local.cluster_tag, {
    Name                              = "${var.eks_cluster_name}-private-${local.azs[count.index]}"
    "kubernetes.io/role/internal-elb" = "1"                  # internal load balancers
    "karpenter.sh/discovery"          = var.eks_cluster_name # Karpenter launches nodes here
  })
}

# create internet gateway

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.eks_cluster_name}-igw"
  }
}

# create route table for public subnets

resource "aws_route_table" "public_route" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "${var.eks_cluster_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_route.id
}

# create elastic IPs + NAT gateways
# one NAT per AZ (default) so losing an AZ does not cut internet egress for the others

locals {
  nat_count = var.single_nat_gateway ? 1 : var.az_count
}

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"

  tags = {
    Name = "${var.eks_cluster_name}-nat-eip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "nat_gw" {
  count         = local.nat_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.eks_cluster_name}-nat-${count.index + 1}"
  }

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.gw]
}

# create one route table per private subnet, pointing at the NAT in the same AZ

resource "aws_route_table" "private_route" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw[var.single_nat_gateway ? 0 : count.index].id
  }

  tags = {
    Name = "${var.eks_cluster_name}-private-rt-${local.azs[count.index]}"
  }
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_route[count.index].id
}
