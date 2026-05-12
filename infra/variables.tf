variable "region" {
  description = "AWS region for the deploy. All resources land here except the few that are pinned to us-east-1 (billing metrics, OIDC if global). Defaults match the build plan."
  type        = string
  default     = "us-west-2"
}

variable "name_prefix" {
  description = "Prefix for all named AWS resources (cluster, service, alarms, log group, ECR repo, etc.). Keep it short; some AWS resource names cap at 32 chars."
  type        = string
  default     = "sre-app"
}

variable "alarm_email" {
  description = "Email address subscribed to the SLO burn-rate alarm SNS topic. The subscription is created in pending state; the recipient must click the AWS confirmation link before notifications fire."
  type        = string
  default     = "jadenscottrazo@gmail.com"
}

variable "github_repo" {
  description = "GitHub repo (owner/name) that the cicd module's OIDC trust policy is scoped to. Anything outside this exact repo cannot assume the deploy role."
  type        = string
  default     = "JadenRazo/sre-reference-app"
}

variable "vpc_cidr" {
  description = "CIDR for the project VPC. /16 gives plenty of room for two /24 public + two /24 private subnets across two AZs."
  type        = string
  default     = "10.0.0.0/16"
}

variable "container_port" {
  description = "Port the Flask app listens on inside the container. Mirrored in the ALB target group, ECS task definition, and security group ingress."
  type        = number
  default     = 8080
}

variable "task_cpu" {
  description = "ECS Fargate task CPU. 256 = 0.25 vCPU. The minimum for Fargate."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "ECS Fargate task memory in MB. 512 is the minimum that pairs with 256 CPU."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of ECS tasks the service runs. Two so the FIS terminate-task experiment has something to take down without dropping below one."
  type        = number
  default     = 2
}

variable "container_image" {
  description = "Initial container image for the ECS task definition. The first apply uses a public placeholder so the service comes up; Phase 4 builds and pushes the real app to ECR and calls update-service. Override at apply time once the ECR image is pushed."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:stable-perl"
}

variable "enable_fis" {
  description = "Whether to provision the AWS FIS experiment template and its IAM role. Some account states reject FIS API calls with SubscriptionRequiredException. When false, the chaos phase uses `aws ecs stop-task` directly (same effect: one task terminated, service auto-recovers)."
  type        = bool
  default     = true
}

variable "slo_target" {
  description = "Availability SLO target as a fraction. 0.99 = 99 percent. The burn-rate alarms compute their thresholds from this."
  type        = number
  default     = 0.99
  validation {
    condition     = var.slo_target > 0.9 && var.slo_target < 1.0
    error_message = "slo_target must be between 0.9 and 1.0 (exclusive)."
  }
}

variable "cert_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener. When set, port 80 redirects to 443 and a second listener is provisioned. Leave null for HTTP-only (dev/demo without a custom domain)."
  type        = string
  default     = null
}
