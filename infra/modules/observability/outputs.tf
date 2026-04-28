output "dashboard_url" {
  description = "Direct console URL to the CloudWatch dashboard."
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.app.dashboard_name}"
}

output "fast_burn_alarm_name" {
  description = "Name of the 1h/14.4x burn-rate alarm."
  value       = aws_cloudwatch_metric_alarm.fast_burn.alarm_name
}

output "slow_burn_alarm_name" {
  description = "Name of the 6h/6x burn-rate alarm."
  value       = aws_cloudwatch_metric_alarm.slow_burn.alarm_name
}

output "sns_alarm_topic_arn" {
  description = "SNS topic ARN that the alarms publish to."
  value       = aws_sns_topic.slo_alerts.arn
}

output "fis_experiment_template_id" {
  description = "FIS experiment template ID. Null when enable_fis = false (this account lacks FIS access). Start the experiment via aws fis start-experiment --experiment-template-id ... or from the console when populated."
  value       = var.enable_fis ? aws_fis_experiment_template.stop_tasks[0].id : null
}
