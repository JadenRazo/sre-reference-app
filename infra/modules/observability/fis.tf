resource "aws_fis_experiment_template" "stop_tasks" {
  description = "Terminate one ECS task tagged FIS-Target=true. Verifies SLO survival under controlled chaos."
  role_arn    = aws_iam_role.fis.arn

  action {
    name      = "stop-one-task"
    action_id = "aws:ecs:stop-task"

    target {
      key   = "Tasks"
      value = "ecs-tasks"
    }
  }

  target {
    name           = "ecs-tasks"
    resource_type  = "aws:ecs:task"
    selection_mode = "COUNT(1)"

    resource_tag {
      key   = "FIS-Target"
      value = "true"
    }

    parameters = {
      cluster = var.ecs_cluster_arn
    }
  }

  # Production would attach a CloudWatch alarm here so the experiment auto-
  # aborts if the burn-rate alarm goes critical. For build-day demo the
  # experiment runs to completion (one task termination) and stops on its own.
  stop_condition {
    source = "none"
  }

  tags = {
    Name = "${var.name_prefix}-stop-tasks"
  }
}
