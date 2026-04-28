variable "name_prefix" {
  type        = string
  description = "Prefix applied to Name tags on networking resources for console clarity."

  validation {
    condition     = length(var.name_prefix) > 0 && length(var.name_prefix) <= 32
    error_message = "name_prefix must be between 1 and 32 characters."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC. Subnet CIDRs in this module assume a /16 in the 10.0.0.0/16 shape."
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}
