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
  nat_gateway_subnets = var.nat_gateway_mode == "Zonal" ? {
    for az, subnet_name in local.public_subnet_by_az :
    az => subnet_name
    if contains(local.private_subnet_azs, az)
  } : {}
}

// Create the VPC and configure its DNS behavior.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  lifecycle {
    precondition {
      condition     = var.nat_gateway_mode != "Zonal" || length(var.public_subnets) > 0
      error_message = "Zonal NAT gateways require public subnets."
    }

    precondition {
      condition = var.nat_gateway_mode != "Zonal" || alltrue([
        for subnet in values(var.private_subnets) :
        contains(local.public_subnet_azs, subnet.availability_zone)
      ])
      error_message = "Zonal NAT gateways require a public subnet in every AZ that has a private subnet."
    }

    precondition {
      condition     = !var.enable_s3_endpoint || length(var.private_subnets) > 0
      error_message = "The S3 gateway endpoint requires at least one private subnet."
    }
  }

  tags = merge(local.common_tags, {
    Name = var.vpc_name
  })
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
  for_each = var.nat_gateway_mode == "None" ? {} : var.private_subnets

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = var.nat_gateway_mode == "Regional" ? (
    aws_nat_gateway.regional[0].id
  ) : try(aws_nat_gateway.zonal[each.value.availability_zone].id, null)

  lifecycle {
    precondition {
      condition     = var.nat_gateway_mode != "Zonal" || contains(keys(aws_nat_gateway.zonal), each.value.availability_zone)
      error_message = "Zonal NAT gateways require a public subnet in every AZ that has a private subnet."
    }
  }
}

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_endpoint ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for route_table in aws_route_table.private : route_table.id]

  tags = merge(local.common_tags, {
    Name = "${var.vpc_name}-s3"
  })
}
