output "alb_dns_name" {
  description = "Public DNS of the ALB. Hit this for smoke tests and load generation."
  value       = module.service.alb_dns_name
}

output "alb_url" {
  description = "Convenience URL form of alb_dns_name."
  value       = "http://${module.service.alb_dns_name}"
}

output "ecr_repository_url" {
  description = "ECR repo URL for `docker push` in Phase 4 and the GH Actions workflow in Phase 7."
  value       = module.service.ecr_repository_url
}

output "ecr_repository_name" {
  description = "Bare ECR repo name (without registry prefix). Useful for `aws ecr describe-images` calls."
  value       = module.service.ecr_repository_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name. Used by `aws ecs update-service`, `aws ecs describe-services`, and the GH Actions workflow."
  value       = module.service.ecs_cluster_name
}

output "ecs_service_name" {
  description = "ECS service name. Same use cases as ecs_cluster_name."
  value       = module.service.ecs_service_name
}

output "task_definition_family" {
  description = "ECS task definition family. The CI/CD pipeline registers new revisions of this family on each deploy."
  value       = module.service.task_definition_family
}

output "log_group_name" {
  description = "CloudWatch Logs group that ECS tasks write structured JSON logs to. Tail with `aws logs tail <name> --follow`."
  value       = module.service.log_group_name
}

output "dashboard_url" {
  description = "Direct URL to the CloudWatch dashboard."
  value       = module.observability.dashboard_url
}

output "fast_burn_alarm_name" {
  description = "Name of the fast-burn (1h, 14.4x) SLO alarm. State is queryable via `aws cloudwatch describe-alarms`."
  value       = module.observability.fast_burn_alarm_name
}

output "slow_burn_alarm_name" {
  description = "Name of the slow-burn (6h, 6x) SLO alarm."
  value       = module.observability.slow_burn_alarm_name
}

output "fis_experiment_template_id" {
  description = "FIS experiment template ID. Start the experiment from the FIS console using this ID, or `aws fis start-experiment`."
  value       = module.observability.fis_experiment_template_id
}

output "sns_alarm_topic_arn" {
  description = "SNS topic the burn-rate alarms publish to. Subscriptions are pending until confirmed via email."
  value       = module.observability.sns_alarm_topic_arn
}

output "deploy_role_arn" {
  description = "IAM role ARN that GitHub Actions assumes via OIDC. Set `ROLE_TO_ASSUME` in the workflow to this."
  value       = module.cicd.deploy_role_arn
}

output "github_oidc_provider_arn" {
  description = "OIDC provider ARN for token.actions.githubusercontent.com. Created once per account."
  value       = module.cicd.github_oidc_provider_arn
}
