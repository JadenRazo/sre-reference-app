# GitHub OIDC provider. AWS now caches and auto-rotates the thumbprints
# server-side; the field is largely vestigial. Real values are still
# provided here to keep terraform plan from showing diffs and to make the
# resource explicit about what it trusts.
#
# If a GitHub OIDC provider already exists in this account (common when
# multiple repos share an account), this resource will fail to create.
# Recovery:
#   terraform import module.cicd.aws_iam_openid_connect_provider.github \
#     arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_policy_document" "deploy_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # :sub StringLike with a trailing :* matches any branch, tag, or PR in
    # the repo. Build-day convenience. Production should narrow to
    # "repo:OWNER/REPO:ref:refs/heads/main" or
    # "repo:OWNER/REPO:environment:production".
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "${var.name_prefix}-gh-deploy"
  assume_role_policy = data.aws_iam_policy_document.deploy_assume.json
}
