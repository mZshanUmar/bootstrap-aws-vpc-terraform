output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "internet_gateway_id" {
  description = "ID of the internet gateway, or null when no public subnets are configured."
  value       = length(aws_internet_gateway.this) > 0 ? aws_internet_gateway.this[0].id : null
}

output "public_subnet_ids" {
  description = "Public subnet IDs keyed by subnet name."
  value       = { for name, subnet in aws_subnet.public : name => subnet.id }
}

output "private_subnet_ids" {
  description = "Private subnet IDs keyed by subnet name."
  value       = { for name, subnet in aws_subnet.private : name => subnet.id }
}

output "public_route_table_ids" {
  description = "Public route table IDs keyed by subnet name."
  value       = { for name, route_table in aws_route_table.public : name => route_table.id }
}

output "private_route_table_ids" {
  description = "Private route table IDs keyed by subnet name."
  value       = { for name, route_table in aws_route_table.private : name => route_table.id }
}
