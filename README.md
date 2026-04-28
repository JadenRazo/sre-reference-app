# sre-reference-app

A reference SRE project deployed to AWS: Flask app on ECS Fargate behind an ALB, with structured logging, CloudWatch dashboards, SLO burn-rate alarms, AWS FIS chaos experiments, and a GitHub Actions OIDC deploy pipeline. Built as a portfolio piece to demonstrate the practices that show up in real on-call work, not the demo-day version.

> Status: in active build. The full README, architecture diagram, SLO numbers, screenshots, and post drafts land in Phase 8. This skeleton is a placeholder until the build completes.

## What this is meant to demonstrate

- Production-shaped infrastructure as code (Terraform, modular, no inline IAM JSON, no hardcoded ARNs).
- Observability designed in from the first commit, not retrofitted (structured JSON logs, custom CloudWatch dashboard, fast-burn and slow-burn SLO alarms).
- Controlled fault injection with AWS FIS, including a written hypothesis/method/result/findings doc.
- Secretless CI/CD via GitHub OIDC federation, no static AWS keys in repo or in GitHub secrets.
- Documentation that reads like an operator's notes: a runbook, a post-mortem template, an architecture doc.

## Quickstart (placeholder)

The full quickstart with copy-paste commands lands in Phase 8. Today the high-level shape is:

```bash
# Local app
cd app && docker build -t sre-app:local . && docker run -p 8080:8080 sre-app:local

# Infra
cd infra && terraform init && terraform plan -var "region=us-west-2"
```

## Repo layout

```
app/                 Flask app + Dockerfile
infra/               Terraform root + 4 modules (network, service, observability, cicd)
docs/                Architecture, SLOs, chaos experiments, post-mortem template
runbooks/            Operator runbooks
screenshots/         Build-day screenshots referenced from this README
.github/workflows/   OIDC-based deploy pipeline
.claude/agents/      Project-scoped subagents used during the build
```

## Build phases

The build runs through 9 phases tagged in git as `phase-1-complete` through `phase-8-complete`. See `PLAN.md` for the full plan and `PROGRESS.md` for the live phase log.

## License

MIT.
