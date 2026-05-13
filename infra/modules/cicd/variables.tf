variable "name_prefix" {
  description = "Prefix for IAM resource names."
  type        = string
}

variable "github_repo" {
  description = "GitHub repo in owner/name form (e.g. JadenRazo/sre-reference-app). The OIDC trust policy is scoped to this exact repo via the :sub claim."
  type        = string
  validation {
    condition     = can(regex("^[^/[:space:]]+/[^/[:space:]]+$", var.github_repo))
    error_message = "github_repo must be in owner/name form."
  }
}

variable "ecr_repository_arn" {
  description = "ECR repository ARN the deploy role can push to."
  type        = string
}

variable "ecs_cluster_arn" {
  description = "ECS cluster ARN. Conditions ECS task-listing permissions to this cluster."
  type        = string
}

variable "ecs_service_arn" {
  description = "ECS service ARN the deploy role can update."
  type        = string
}

variable "task_role_arn" {
  description = "Task role ARN. The deploy role gets iam:PassRole on this role only."
  type        = string
}

variable "task_execution_arn" {
  description = "Task execution role ARN. The deploy role gets iam:PassRole on this role only."
  type        = string
}

variable "task_definition_family" {
  description = "ECS task definition family. Reserved for future scoping of RegisterTaskDefinition (currently unscopable in IAM)."
  type        = string
}

variable "app_log_group_arn" {
  description = "CloudWatch log group ARN for the ECS app. Scopes the logs-read policy to this specific log group instead of wildcard resource."
  type        = string
}
