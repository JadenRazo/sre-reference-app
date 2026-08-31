# Security policy

## Supported code

Security fixes are made against the latest `main` branch. Historical phase tags, screenshots, and evidence captures are not maintained release lines.

## Reporting

Use GitHub private vulnerability reporting through the repository's **Security** tab when available. Otherwise email `contact@jadenrazo.dev` with the affected commit or path, impact, and a minimal reproduction.

Do not open a public issue containing credentials, Terraform state, AWS account details, reachable infrastructure, or a working exploit.

## Scope

Reports involving the Flask service, container boundary, Terraform modules, IAM/OIDC trust, CI workflows, or observability configuration are in scope. Dependency vulnerabilities should also be reported to the relevant upstream project.
