variable "aws_region" {
  description = "AWS region in which to create the VPC."
  type        = string
}

variable "vpc_name" {
  description = "Name used for the VPC and its resources."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC."
  type        = string

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
  default = {}

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
  default = {}

  validation {
    condition = alltrue([
      for subnet in values(var.private_subnets) : can(cidrnetmask(subnet.cidr_block))
    ])
    error_message = "Every private subnet cidr_block must be a valid IPv4 CIDR block."
  }
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

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
