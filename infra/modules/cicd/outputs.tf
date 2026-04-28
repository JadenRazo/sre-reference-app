output "deploy_role_arn" {
  description = "IAM role ARN that GitHub Actions assumes via OIDC. Set as ROLE_TO_ASSUME in the workflow."
  value       = aws_iam_role.deploy.arn
}

output "github_oidc_provider_arn" {
  description = "OIDC provider ARN. There is at most one of these per account."
  value       = aws_iam_openid_connect_provider.github.arn
}
