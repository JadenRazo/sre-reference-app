# Policy 1: ECR push. GetAuthorizationToken must be account-wide (it has
# no resource scope in IAM); the rest are scoped to the project repo only.
data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "ECRPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [var.ecr_repository_arn]
  }
}

resource "aws_iam_policy" "ecr_push" {
  name   = "${var.name_prefix}-gh-deploy-ecr"
  policy = data.aws_iam_policy_document.ecr_push.json
}

resource "aws_iam_role_policy_attachment" "ecr_push" {
  role       = aws_iam_role.deploy.name
  policy_arn = aws_iam_policy.ecr_push.arn
}

# Policy 2: ECS deploy. UpdateService and DescribeServices scoped to the
# specific service. Task def actions cannot be scoped to a family in IAM
# (the resource ARN includes the revision, which doesn't exist yet at
# RegisterTaskDefinition time), so they're account-wide. List/DescribeTasks
# is conditioned to the project cluster.
data "aws_iam_policy_document" "ecs_deploy" {
  statement {
    sid       = "ECSService"
    actions   = ["ecs:DescribeServices", "ecs:UpdateService"]
    resources = [var.ecs_service_arn]
  }

  statement {
    sid       = "ECSTaskDef"
    actions   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
    resources = ["*"]
  }

  # register-task-definition counts as a TagResource action when the call
  # passes tags, which the deploy workflow does to preserve FIS-Target.
  # Scope tightly to revisions of THIS family, not all task definitions.
  statement {
    sid     = "ECSTagTaskDef"
    actions = ["ecs:TagResource", "ecs:UntagResource"]
    resources = [
      "arn:${data.aws_partition.current.partition}:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:task-definition/${var.task_definition_family}:*",
    ]
  }

  statement {
    sid       = "ECSTasks"
    actions   = ["ecs:ListTasks", "ecs:DescribeTasks"]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [var.ecs_cluster_arn]
    }
  }

  statement {
    sid       = "ECSCluster"
    actions   = ["ecs:DescribeClusters"]
    resources = [var.ecs_cluster_arn]
  }
}

resource "aws_iam_policy" "ecs_deploy" {
  name   = "${var.name_prefix}-gh-deploy-ecs"
  policy = data.aws_iam_policy_document.ecs_deploy.json
}

resource "aws_iam_role_policy_attachment" "ecs_deploy" {
  role       = aws_iam_role.deploy.name
  policy_arn = aws_iam_policy.ecs_deploy.arn
}

# Policy 3: PassRole. Most security-sensitive permission in the deploy
# bundle. Scoped to exactly the two ECS task roles, with iam:PassedToService
# locked to ecs-tasks.amazonaws.com so the deploy role cannot hand these
# roles to (e.g.) a Lambda or EC2 instance.
data "aws_iam_policy_document" "pass_role" {
  statement {
    sid       = "PassECSRolesToECSOnly"
    actions   = ["iam:PassRole"]
    resources = [var.task_role_arn, var.task_execution_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "pass_role" {
  name   = "${var.name_prefix}-gh-deploy-passrole"
  policy = data.aws_iam_policy_document.pass_role.json
}

resource "aws_iam_role_policy_attachment" "pass_role" {
  role       = aws_iam_role.deploy.name
  policy_arn = aws_iam_policy.pass_role.arn
}

# Policy 4: CloudWatch Logs read. Useful for debugging deploy failures from
# within the GH Actions workflow. CloudWatch Logs IAM does not support
# scoping these read actions to a specific log group reliably across all
# regions; account-wide read is the documented pattern.
data "aws_iam_policy_document" "logs_read" {
  statement {
    sid = "LogsRead"
    actions = [
      "logs:GetLogEvents",
      "logs:DescribeLogStreams",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "logs_read" {
  name   = "${var.name_prefix}-gh-deploy-logs"
  policy = data.aws_iam_policy_document.logs_read.json
}

resource "aws_iam_role_policy_attachment" "logs_read" {
  role       = aws_iam_role.deploy.name
  policy_arn = aws_iam_policy.logs_read.arn
}
