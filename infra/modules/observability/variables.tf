variable "name_prefix" {
  description = "Prefix for resource names (dashboard, alarms, SNS topic, FIS template)."
  type        = string
}

variable "region" {
  description = "AWS region. Used to build the dashboard console URL."
  type        = string
}

variable "alarm_email" {
  description = "Email address subscribed to the SLO alert SNS topic. Subscription stays in pending state until the recipient clicks the AWS confirmation link."
  type        = string
}

variable "slo_target" {
  description = "Availability SLO target as a fraction. Burn-rate alarm thresholds are computed from (1 - slo_target) * burn_rate."
  type        = number
  default     = 0.99
  validation {
    condition     = var.slo_target > 0.9 && var.slo_target < 1.0
    error_message = "slo_target must be between 0.9 and 1.0 (exclusive)."
  }
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (e.g. app/sre-app-alb/abc123) used in CloudWatch metric dimensions."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix used in CloudWatch metric dimensions."
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name. Used in dashboard metric dimensions."
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name. Used in dashboard metric dimensions."
  type        = string
}

variable "ecs_cluster_arn" {
  description = "ECS cluster ARN. FIS targets are scoped to this cluster via the experiment template's parameters block."
  type        = string
}

variable "enable_fis" {
  description = "Whether to create the AWS FIS experiment template and its IAM role. Some account states reject FIS API calls with SubscriptionRequiredException; set to false in that case and use `aws ecs stop-task` directly for the chaos phase. The dashboard, alarms, and SNS resources are unaffected by this flag."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "KMS CMK ARN used to encrypt the SNS topic at rest (CKV_AWS_26). Passed in from the service module's shared logs CMK."
  type        = string
}
