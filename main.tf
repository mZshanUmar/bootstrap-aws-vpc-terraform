// Apply shared project tags to all resources, with resource-specific tags merged in below.
locals {
  common_tags = merge(var.tags, {
    Project = var.vpc_name
  })

  private_subnet_azs = toset([
    for subnet in values(var.private_subnets) : subnet.availability_zone
  ])
  public_subnet_azs = toset([
    for subnet in values(var.public_subnets) : subnet.availability_zone
  ])
  public_subnet_by_az = {
    for az in local.public_subnet_azs :
    az => sort([
      for name, subnet in var.public_subnets : name
      if subnet.availability_zone == az
    ])[0]
  }
  zonal_nat_gateway_azs = var.zonal_nat_gateway_availability_zones == null ? (
    local.private_subnet_azs
  ) : toset(var.zonal_nat_gateway_availability_zones)
  nat_gateway_subnets = var.nat_gateway_mode == "Zonal" ? {
    for az, subnet_name in local.public_subnet_by_az :
    az => subnet_name
    if contains(local.private_subnet_azs, az) && contains(local.zonal_nat_gateway_azs, az)
  } : {}
}

// Create the VPC and configure its DNS behavior.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  lifecycle {
    precondition {
      condition = var.nat_gateway_mode != "Zonal" || (
        var.zonal_nat_gateway_availability_zones == null
        ? length(var.public_subnets) > 0
        : length(var.zonal_nat_gateway_availability_zones) == 0 || length(var.public_subnets) > 0
      )
      error_message = "Zonal NAT gateways require public subnets."
    }

    precondition {
      condition = var.nat_gateway_mode != "Zonal" || (
        var.zonal_nat_gateway_availability_zones == null
        ? alltrue([
          for subnet in values(var.private_subnets) :
          contains(local.public_subnet_azs, subnet.availability_zone)
        ])
        : alltrue([
          for az in var.zonal_nat_gateway_availability_zones :
          contains(local.private_subnet_azs, az) && contains(local.public_subnet_azs, az)
        ])
      )
      error_message = "Zonal NAT gateways require public and private subnets in every selected AZ; when no AZ list is provided, every private-subnet AZ needs a public subnet."
    }
  }

  tags = merge(local.common_tags, {Name = var.vpc_name})
}

// An internet gateway is only needed when the configuration includes public subnets.
resource "aws_internet_gateway" "this" {
  count  = length(var.public_subnets) > 0 || var.nat_gateway_mode == "Regional" ? 1 : 0
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
    Name = "rtb-${each.key}-public"
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
    Name = "rtb-${each.key}-private"
    Tier = "private"
  })
}

// Attach each private subnet to its matching private route table.
resource "aws_route_table_association" "private" {
  for_each = var.private_subnets

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_eip" "nat" {
  for_each = local.nat_gateway_subnets

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-nat-${each.key}"
  })
}

resource "aws_nat_gateway" "zonal" {
  for_each = local.nat_gateway_subnets

  availability_mode = "zonal"
  allocation_id     = aws_eip.nat[each.key].id
  subnet_id         = aws_subnet.public[each.value].id

  depends_on = [aws_internet_gateway.this]

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-nat-${each.key}"
  })
}

resource "aws_nat_gateway" "regional" {
  count = var.nat_gateway_mode == "Regional" ? 1 : 0

  availability_mode = "regional"
  vpc_id            = aws_vpc.this.id

  depends_on = [aws_internet_gateway.this]

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-nat-regional"
  })
}

resource "aws_route" "private_nat" {
  for_each = var.nat_gateway_mode == "Regional" ? var.private_subnets : (
    var.nat_gateway_mode == "Zonal" ? {
      for name, subnet in var.private_subnets :
      name => subnet
      if contains(keys(local.nat_gateway_subnets), subnet.availability_zone)
    } : {}
  )

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = var.nat_gateway_mode == "Regional" ? (
    aws_nat_gateway.regional[0].id
  ) : try(aws_nat_gateway.zonal[each.value.availability_zone].id, null)
}