variable "aws_region" {
  description = "AWS region in which to create the VPC."
  type        = string
}

variable "vpc_name" {
  description = "Name used for the VPC and its resources."
  type        = string
}

variable "enable_dns_support" {
  description = "Enable DNS resolution in the VPC."
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC."
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnets" {
  description = "Public subnet definitions keyed by subnet name. An empty map creates no internet gateway."
  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))
  default = {
    public-a = {
      cidr_block        = "10.0.1.0/24"
      availability_zone = "us-east-1a"
    }
  }
  validation {
    condition = alltrue([
      for subnet in values(var.public_subnets) : can(cidrnetmask(subnet.cidr_block))
    ])
    error_message = "Every public subnet cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "private_subnets" {
  description = "Private subnet definitions keyed by subnet name."
  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))
  default = {
    private-a = {
      cidr_block        = "10.0.11.0/24"
      availability_zone = "us-east-1a"
    }
    private-b = {
      cidr_block        = "10.0.12.0/24"
      availability_zone = "us-east-1b"
    }
  }
  validation {
    condition = alltrue([
      for subnet in values(var.private_subnets) : can(cidrnetmask(subnet.cidr_block))
    ])
    error_message = "Every private subnet cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "nat_gateway_mode" {
  description = "NAT gateway availability mode: None or Zonal."
  type        = string
  default     = "None"

  validation {
    condition     = contains(["None", "Zonal"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode must be None or Zonal."
  }
}

variable "zonal_nat_gateway_availability_zones" {
  description = "AZs that receive Zonal NAT gateways. Null uses all private-subnet AZs; an explicit list limits NAT gateways and private NAT routes to those AZs."
  type        = list(string)
  default     = null
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}