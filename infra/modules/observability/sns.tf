resource "aws_sns_topic" "slo_alerts" {
  name = "${var.name_prefix}-slo-alerts"
}

# Email subscriptions stay in pending_confirmation until the recipient clicks
# the AWS-sent confirmation link. The alarm itself fires regardless; only the
# email delivery requires the confirmation.
resource "aws_sns_topic_subscription" "alarm_email" {
  topic_arn = aws_sns_topic.slo_alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}
