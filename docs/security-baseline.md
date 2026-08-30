# Security baseline and accepted lab exceptions

This repository is a reproducible, torn-down SRE lab. It is not a production
service template. Static CI must pass without AWS credentials, and Checkov
exceptions are limited to the controls below. Each exception names the reason
it exists here and the change required before a production deployment.

## Controls hardened in August 2026

- ECR tags are immutable and deploys publish only the commit SHA; there is no
  mutable `latest` tag.
- Public subnets no longer assign public IPs by default, and the VPC default
  security group is explicitly deny-all.
- ALB egress is scoped to the ECS task security group and container port. ECS
  task egress is limited to HTTPS plus TCP/UDP DNS inside the VPC.
- SNS alert data uses the AWS-managed SNS KMS key, invalid ALB headers are
  dropped, and application logs retain 365 days of evidence.
- The deploy role no longer has an unused account-wide CloudWatch Logs read
  policy.
- Every third-party GitHub Action is pinned to an immutable commit SHA. TFLint
  and Terraform are pinned to explicit tool versions.
- Deployment is manual-only and requires the `deploy-lab` confirmation. A push
  to `main` cannot create or update AWS resources.

## Accepted exceptions

| Checkov control | Why it is accepted in this lab | Required before production |
| --- | --- | --- |
| `CKV_AWS_2`, `CKV_AWS_103`, `CKV_AWS_260`, `CKV_AWS_378`, `CKV2_AWS_20` | The measured experiment used a temporary ALB DNS name and HTTP end to end; no domain or ACM certificate was provisioned. | Add an ACM certificate, TLS 1.2+ HTTPS listener, HTTP redirect, and an explicit decision on re-encryption to the target. |
| `CKV_AWS_91` | ALB access logging adds an S3 log bucket and policy to a short-lived, stateless experiment. Request evidence is kept in CloudWatch application metrics and logs. | Enable ALB access logs to a protected, lifecycle-managed S3 bucket. |
| `CKV_AWS_136` | ECR images are explicitly encrypted with AWS-owned AES-256 to avoid a persistent customer-managed-key charge after the lab is torn down. | Use a customer-managed KMS key with rotation, least-privilege grants, and an owner. |
| `CKV_AWS_150` | Deletion protection would block the documented one-command teardown and extend paid lab runtime. | Enable deletion protection and require a reviewed break-glass procedure. |
| `CKV_AWS_158` | CloudWatch Logs provides default at-rest encryption; a customer-managed key would be a persistent paid resource for this disposable lab. | Associate a rotated customer-managed KMS key and test the CloudWatch Logs key policy. |
| `CKV2_AWS_11` | VPC Flow Logs and their destination would outlive the short experiment unless separately cleaned up. Traffic behavior was measured through ALB, ECS, and application telemetry. | Enable VPC Flow Logs with a defined retention period, encryption, access policy, and query/runbook ownership. |
| `CKV2_AWS_28` | AWS WAF adds recurring cost without changing the controlled failure hypothesis being tested. | Put a managed WAF policy in front of the public ALB and validate blocking/false-positive behavior. |

These exceptions are not a baseline file that hides future findings. CI lists
the exact IDs, so any new Checkov control fails the pull request and requires a
code fix or an explicit addition to this document.

## Reproduce the static gate

```bash
cd infra
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
tflint --init
tflint --recursive --format=compact
checkov -d . --framework terraform \
  --skip-check CKV_AWS_2,CKV_AWS_91,CKV_AWS_103,CKV_AWS_136,CKV_AWS_150,CKV_AWS_158,CKV_AWS_260,CKV_AWS_378,CKV2_AWS_11,CKV2_AWS_20,CKV2_AWS_28
```
