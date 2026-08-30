# Two AZs is enough for the reference app's ALB + ECS Fargate service.
# Filtering on state = "available" avoids picking an AZ that AWS has marked
# impaired or restricted for this account.
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  public_subnets = [
    { cidr = "10.0.1.0/24", az_index = 0 },
    { cidr = "10.0.2.0/24", az_index = 1 },
  ]

  private_subnets = [
    { cidr = "10.0.10.0/24", az_index = 0 },
    { cidr = "10.0.20.0/24", az_index = 1 },
  ]
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

# The VPC default security group is not used. Managing it explicitly prevents
# resources added later from inheriting its permissive same-group rules.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.this.id

  ingress = []
  egress  = []

  tags = {
    Name = "${var.name_prefix}-default-deny"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  count = length(local.public_subnets)

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.public_subnets[count.index].cidr
  availability_zone = local.azs[local.public_subnets[count.index].az_index]
  # Internet-facing ALBs and NAT gateways obtain addresses explicitly; other
  # resources placed in this subnet should not receive a public IP by default.
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-public-${local.azs[local.public_subnets[count.index].az_index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  count = length(local.private_subnets)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.private_subnets[count.index].cidr
  availability_zone       = local.azs[local.private_subnets[count.index].az_index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-private-${local.azs[local.private_subnets[count.index].az_index]}"
    Tier = "private"
  }
}

# Single NAT gateway in the first public subnet to keep build-day cost low
# (NAT GW is ~$32/mo + data; running one-per-AZ would triple that on a 3-AZ
# layout). Production should run one NAT GW per AZ so a single AZ outage
# does not blackhole egress for the surviving private subnets.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat-eip"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.name_prefix}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${var.name_prefix}-private-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
