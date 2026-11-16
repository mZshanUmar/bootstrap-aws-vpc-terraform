// Apply shared project tags to all resources, with resource-specific tags merged in below.
locals {
  common_tags = merge(var.tags, {
    Project = var.vpc_name
  })
}

// Create the VPC and configure its DNS behavior.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(local.common_tags, {
    Name = var.vpc_name
  })
}

// An internet gateway is only needed when the configuration includes public subnets.
resource "aws_internet_gateway" "this" {
  count  = length(var.public_subnets) > 0 ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-igw"
  })
}

// Public subnets map launched instances to public IP addresses.
resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = each.key
    Tier = "public"
  })
}

// Send public-subnet traffic destined outside the VPC through the internet gateway.
resource "aws_route_table" "public" {
  for_each = var.public_subnets

  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }

  tags = merge(local.common_tags, {
    Name = "${each.key}-public"
    Tier = "public"
  })
}

// Attach each public subnet to its matching public route table.
resource "aws_route_table_association" "public" {
  for_each = var.public_subnets

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public[each.key].id
}

// Private subnets do not automatically assign public IP addresses.
resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  tags = merge(local.common_tags, {
    Name = each.key
    Tier = "private"
  })
}

// Private route tables have no internet route by default.
resource "aws_route_table" "private" {
  for_each = var.private_subnets

  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${each.key}-private"
    Tier = "private"
  })
}

// Attach each private subnet to its matching private route table.
resource "aws_route_table_association" "private" {
  for_each = var.private_subnets

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}
