# Burn-rate alarms use metric math: e1 = m1 / m2 with a divide-by-zero guard.
# m1 = sum of 5xx, m2 = sum of total requests. Both summed over the alarm
# window (1h fast-burn, 6h slow-burn). Period is set on the metric block,
# not the alarm root, when metric_query is used.
#
# treat_missing_data = "notBreaching" so periods of zero traffic don't false-fire.

resource "aws_cloudwatch_metric_alarm" "fast_burn" {
  alarm_name          = "${var.name_prefix}-fast-burn"
  alarm_description   = "5xx error rate over 1h exceeds 14.4x SLO burn rate. Threshold = (1 - slo_target) * 14.4."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = local.fast_burn_threshold
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.slo_alerts.arn]
  ok_actions    = [aws_sns_topic.slo_alerts.arn]

  metric_query {
    id          = "e1"
    expression  = "IF(m2 > 0, m1 / m2, 0)"
    label       = "Error ratio"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 3600
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
      }
    }
  }

  metric_query {
    id = "m2"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 3600
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "slow_burn" {
  alarm_name          = "${var.name_prefix}-slow-burn"
  alarm_description   = "5xx error rate over 6h exceeds 6x SLO burn rate. Threshold = (1 - slo_target) * 6."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = local.slow_burn_threshold
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.slo_alerts.arn]
  ok_actions    = [aws_sns_topic.slo_alerts.arn]

  metric_query {
    id          = "e1"
    expression  = "IF(m2 > 0, m1 / m2, 0)"
    label       = "Error ratio"
    return_data = true
  }

  metric_query {
    id = "m1"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 21600
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
      }
    }
  }

  metric_query {
    id = "m2"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 21600
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
      }
    }
  }
}
