output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the two public subnets, ordered by AZ index."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the two private subnets, ordered by AZ index."
  value       = aws_subnet.private[*].id
}

output "vpc_endpoint_security_group_id" {
  description = "Security group ID attached to all Interface VPC Endpoints in this VPC."
  value       = aws_security_group.vpc_endpoints.id
}

output "s3_prefix_list_id" {
  description = "Managed prefix list ID for the S3 Gateway VPC Endpoint (for use in SG egress rules)."
  value       = aws_vpc_endpoint.s3.prefix_list_id
}
