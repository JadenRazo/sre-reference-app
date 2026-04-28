data "aws_iam_policy_document" "fis_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["fis.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fis" {
  count              = var.enable_fis ? 1 : 0
  name               = "${var.name_prefix}-fis"
  assume_role_policy = data.aws_iam_policy_document.fis_assume.json
}

# AWSFaultInjectionSimulatorECSAccess is the AWS-managed policy for FIS to
# call ECS APIs (StopTask, DescribeTasks, etc.). Documented at
# https://docs.aws.amazon.com/fis/latest/userguide/security-iam-awsmanpol.html
resource "aws_iam_role_policy_attachment" "fis_ecs" {
  count      = var.enable_fis ? 1 : 0
  role       = aws_iam_role.fis[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorECSAccess"
}
