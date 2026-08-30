variable "name_prefix" {
  description = "Prefix for resource names. Capped at 24 chars to leave headroom for the -alb / -tg / -cluster suffixes under the AWS 32-char name caps."
  type        = string
  validation {
    condition     = length(var.name_prefix) <= 24
    error_message = "name_prefix must be 24 characters or fewer."
  }
}

variable "vpc_id" {
  description = "VPC the ALB and tasks live in."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR used to scope ECS task DNS egress."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (one per AZ) where the internet-facing ALB attaches."
  type        = list(string)
  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "ALB requires at least 2 subnets in distinct AZs."
  }
}

variable "private_subnet_ids" {
  description = "Private subnet IDs (one per AZ) where ECS tasks run. Tasks reach the internet via the NAT gateway in the network module."
  type        = list(string)
  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "Service requires at least 2 private subnets for AZ redundancy."
  }
}

variable "container_port" {
  description = "Port the container listens on. Mirrored in the target group, security group rule, and task definition."
  type        = number
  default     = 8080
}

variable "container_image" {
  description = "Initial container image for the task definition. The first apply uses a public placeholder so the service comes up; Phase 4 builds the real app, pushes to ECR, and registers a new task def revision via update-service. The lifecycle rule on the service ignores task_definition changes so terraform apply does not revert it."
  type        = string
}

variable "task_cpu" {
  description = "Fargate CPU units. 256 = 0.25 vCPU (Fargate minimum)."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate memory in MB. 512 is the minimum that pairs with 256 CPU."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of running tasks. Two so the FIS terminate-one-task experiment has something to take down without dropping below one."
  type        = number
  default     = 2
}
