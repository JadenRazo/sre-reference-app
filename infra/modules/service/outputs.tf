output "ecr_repository_url" {
  description = "ECR repo URL for docker push."
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_name" {
  description = "Bare ECR repo name."
  value       = aws_ecr_repository.app.name
}

output "ecr_repository_arn" {
  description = "ECR repo ARN, scoped IAM policies use this."
  value       = aws_ecr_repository.app.arn
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.app.name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN, used by FIS target scoping and IAM conditions."
  value       = aws_ecs_cluster.app.arn
}

output "ecs_service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.app.name
}

output "ecs_service_arn" {
  description = "ECS service ARN."
  value       = aws_ecs_service.app.id
}

output "alb_dns_name" {
  description = "Public DNS for the ALB."
  value       = aws_lb.app.dns_name
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (e.g. app/sre-app-alb/abc123) used in CloudWatch dimensions."
  value       = aws_lb.app.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix used in CloudWatch dimensions."
  value       = aws_lb_target_group.app.arn_suffix
}

output "task_definition_family" {
  description = "ECS task definition family. CI/CD registers new revisions of this family."
  value       = aws_ecs_task_definition.app.family
}

output "log_group_name" {
  description = "CloudWatch log group ECS tasks write to."
  value       = aws_cloudwatch_log_group.app.name
}

output "task_role_arn" {
  description = "ECS task role ARN."
  value       = aws_iam_role.task.arn
}

output "task_execution_role_arn" {
  description = "ECS task execution role ARN."
  value       = aws_iam_role.task_execution.arn
}

output "log_group_arn" {
  description = "CloudWatch log group ARN. Used to scope IAM read policies to this specific log group."
  value       = aws_cloudwatch_log_group.app.arn
}

output "kms_logs_key_arn" {
  description = "KMS CMK ARN used to encrypt the ECS app log group. Passed to other modules that need to share the key (e.g. SNS, ECR)."
  value       = aws_kms_key.logs.arn
}
