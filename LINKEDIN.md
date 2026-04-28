# LinkedIn drafts

This file lives in the repo because the build itself is part of the artifact. The build log entries below get synthesized into three polished post drafts in Phase 8.

## Style guide (enforced by the technical-writer subagent)

- **No em dashes.** Restructure with commas, periods, or parentheses.
- **ASCII only.** No smart quotes, no `…`. Use `'`, `"`, `...`.
- **Banned phrases:** `delve`, `leverage` (as a verb when "use" works), `robust`, `tapestry`, `intricate`, `comprehensive solution`, `in the realm of`, `at the end of the day`, `it's worth noting`, `in today's fast-paced`, `game-changer`, `unleash`, `cutting-edge`, `excited to share`, `thrilled to announce`, `seamless`, `empower`, `revolutionize`, `next-generation`, `world-class`.
- **Lead with a number or a concrete observation, not a generic intro.**
- **First two lines must hook before LinkedIn's "see more" cut.** Mobile cuts at ~210 chars; what comes before that is your only shot at click-through.
- No emojis. No `🚀`. No "I'm excited to share that...".

## Format budgets

| Format | Char budget | Phase target |
|---|---|---|
| Long-form story | 1200-1700 | Phase 6 (chaos, the headline post) |
| Single takeaway | 400-700 | Phase 7 (OIDC vs static keys) |
| Numbered list | 800-1200 | Phase 4-5 build-log synthesis |

## Build log

Phase-by-phase notes for later synthesis. Each entry is rough; the writer agent polishes them into final drafts in Phase 8.

### Phase 1 - Bootstrap - 2026-04-28
- Created public repo `JadenRazo/sre-reference-app`. Three project-scoped subagents in place to enforce style and infra hygiene before any code lands.
- The enforcement mechanism itself is a teachable moment: the reviewer agent greps for em dashes and banned phrases on every commit. If you can't grep for it, you can't enforce it.
- Surprise: writing the agent prompts forced me to articulate banned phrases I'd been letting slide for years in my own writing.

### Phase 2 - App + container - 2026-04-28
- Flask app + gunicorn behind a python:3.12-slim image. Two endpoints: `/health` always 200, `/` returns 500 with probability ERROR_RATE (default 0.05) so the SLO alarms have signal.
- Smoke test: 50 requests, 46x 200, 4x 500 (8% baseline, within expected variance for n=50).
- Surprise: my first JsonFormatter used `self.formatTime(record, "%Y-%m-%dT%H:%M:%S.%fZ")` and shipped literal `.%fZ` in every timestamp because Python's logging.Formatter uses `time.strftime` which doesn't expand `%f`. Switched to `datetime.fromtimestamp(record.created, tz=timezone.utc)`. Lesson: structured logs are only as good as the parser that reads them; CloudWatch Logs Insights would have failed silently on the malformed ISO timestamps.
- Second surprise: gunicorn's default access log was duplicating my Flask after_request JSON logs in plain text. Removed `--access-logfile -`, kept only the structured stream. One log format per service is a real rule, not a stylistic preference.

### Phase 3 - Terraform infra - 2026-04-28
- 4 modules (network, service, observability, cicd) authored in parallel by 4 dispatched agents. Each module has a locked input/output contract; agents work against the contract, not against each other.
- terraform plan: 47 resources to add. Validate clean. fmt clean.
- Surprise: writing the cicd module was the most security-thinking-heavy part. The deploy role's PassRole permission has to be scoped to exactly the two ECS task role ARNs AND conditioned on iam:PassedToService=ecs-tasks.amazonaws.com. Without the condition, anyone who pwns the role can hand those task roles to a Lambda or EC2 instance they control.

### Phase 4 - First deploy - 2026-04-28
- terraform apply: 56 of 57 non-data resources created in 3m22s. ALB took 3m22s alone (the standard ALB provisioning latency). Fargate tasks came up on the public nginx placeholder, then we registered a new task definition revision pointing to the real ECR image and called update-service --force-new-deployment.
- Smoke test from local laptop: 20 requests, 19x 200, 1x 500. Exactly the 5% baseline error rate `random.random() < 0.05` should produce. JSON logs land in CloudWatch with full request_id, duration_ms, and remote_addr fields.
- Surprise: AWS FIS hit `SubscriptionRequiredException`. The IAM role and managed policy were fine; FIS itself needed an account-level opt-in I had not done. Documented the recovery path (open the FIS console once, then `terraform apply -target=module.observability.aws_fis_experiment_template.stop_tasks`).
- Second surprise: `aws ecs describe-task-definition` does NOT return tags by default. You have to pass `--include TAGS`. Found out the hard way when register-task-definition rejected my JSON because `tags` came back null. Fifteen minutes of debugging a one-flag fix.

### Phase 5 - Observability + SLO verification - 2026-04-28
- 5 minutes of sustained 5 req/s traffic against the ALB. 1347 requests, 65 5xx, measured error rate 4.83%. Configured ERROR_RATE is 0.05; variance for n=1347 is ~0.6% so 4.83% is one standard deviation below 5%. The randomness behaves as random.random() promised.
- Both burn-rate alarms held OK. The slow-burn alarm saw the live error ratio (0.0484) and confirmed it sat below the 0.06 threshold. The fast-burn alarm returned NonBreaching on missing data because the 1-hour window had no completed period (only 5 min of traffic). treat_missing_data = "notBreaching" did exactly what it was supposed to.
- Surprise: the slow-burn alarm produced a usable datapoint after only 5 minutes despite a 6-hour window. CloudWatch metric math evaluates over the available window when the requested period is incomplete. So the alarm starts working as soon as there is any traffic, not after 6 hours of warm-up. Useful in practice; would have been a footgun if I had not tested it.
- Numbers visible on the dashboard during the run: request count peaked around 5 req/s, p50 latency ~1 ms, p99 latency ~10 ms (Flask + gunicorn doing nothing CPU-heavy), HealthyHostCount steady at 2.

### Phase 6 - Chaos via aws ecs stop-task (FIS substituted) - 2026-04-28
- AWS FIS returned SubscriptionRequiredException on this account (new-account onboarding gate). Substituted aws ecs stop-task for the chaos trigger. Same blast radius, $0 cost, no service-onboarding step. Gated FIS in the terraform module behind enable_fis = false so the project stays clean.
- Killed one of two running tasks during a sustained 8-min ~5 req/s traffic run.
- Service recovered in 78 seconds: replacement task started at T+39s, registered with the target group at T+69s, steady state at T+78s.
- Headline: 4.46% measured error rate during chaos. Lower than the 4.83% Phase 5 baseline. The chaos did not produce a visible 5xx blip. Reason: the surviving task served all traffic cleanly during the 78-second recovery, and the ALB drained the killed task without queueing requests against it (because deregistration_delay was set to 30s, not the AWS default of 300s).
- Both burn-rate alarms stayed OK. 4.46% < 6% slow-burn threshold and < 14.4% fast-burn threshold.
- The most useful thing I learned was not "AWS FIS killed a task" or even "the service recovered." It was that the default deregistration_delay is wrong for any service that wants to survive task termination cleanly. Five minutes of in-flight requests against a dying task is enough to push real workloads above their SLO budget. Tuning that one setting from 300 to 30 was the highest-leverage change in the whole module.

### Phase 7 - CI/CD via OIDC, no static AWS keys - 2026-04-28
- The deploy.yml workflow assumes an IAM role via GitHub's OIDC provider. There is no AWS_ACCESS_KEY_ID stored in the repo, in GitHub Secrets, or anywhere on the runner. GitHub mints a short-lived OIDC token for each run, AWS verifies it against the federated trust policy, and returns 1-hour STS credentials.
- The trust policy on the role (modules/cicd/main.tf) is scoped via StringLike on token.actions.githubusercontent.com:sub to repo:JadenRazo/sre-reference-app:*. A fork or an unrelated repo cannot assume this role even with a copy of the workflow.
- The deploy role's permissions are scoped, not wildcarded. iam:PassRole is locked to exactly the two ECS task role ARNs and conditioned on iam:PassedToService=ecs-tasks.amazonaws.com so the role cannot hand those task roles to a Lambda or EC2 instance. ECR push is scoped to the project repo. ecs:UpdateService is scoped to the project service.
- The most useful interview signal here is not "I used GitHub Actions." It is the absence of secrets. Every static-key CI/CD pipeline I have ever audited had a stale, over-privileged access key buried in repo secrets. OIDC removes the failure mode by removing the artifact.

## Final drafts

(Synthesized in Phase 8.)

### Draft 1: Long-form chaos story

Killed one of two ECS Fargate tasks mid-traffic. The error rate during chaos was 4.46%. Baseline before chaos was 4.83%.

The chaos run was quieter than the steady state. That was not the result I expected.

Setup: two-task service behind an ALB, sustained ~5 req/s, app returns 500 on 5% of requests by design so the SLO alarms have signal. AWS FIS was the original plan, but the account hit SubscriptionRequiredException on a new-account onboarding gate. Substituted aws ecs stop-task. Same blast radius, $0 cost, no service-onboarding step.

Recovery numbers from CloudWatch:
- T+0: task killed
- T+39s: replacement task started
- T+69s: registered with target group
- T+78s: steady state, two healthy targets

Both burn-rate alarms stayed OK the entire run. 4.46% sat below the 6% slow-burn threshold and the 14.4% fast-burn threshold.

The reason the chaos did not produce a visible 5xx blip was not "ECS recovered fast." It was deregistration_delay = 30. The AWS default is 300 seconds. Five minutes of in-flight requests draining against a dying task is enough to push real workloads above their SLO budget on a single bad deploy. Tuning that one setting was the highest-leverage change in the whole module.

The surviving task served all traffic cleanly during the 78-second window. The ALB drained the killed task without queueing requests against it. The chaos was invisible to the SLO.

Repo: github.com/JadenRazo/sre-reference-app

### Draft 2: OIDC takeaway

Every static-key CI/CD pipeline I have ever audited had a stale, over-privileged AWS access key buried in repo secrets. OIDC removes the failure mode by removing the artifact.

Build I just shipped:
- 0 secrets in the repo
- 0 secrets in GitHub Secrets
- 1 IAM role, trust policy scoped via StringLike on the OIDC sub claim to repo:JadenRazo/sre-reference-app:*

GitHub mints a short-lived token per run. AWS verifies it and returns 1-hour STS credentials. A fork cannot assume the role even with a copy of the workflow.

The signal is not "I used GitHub Actions." It is the absence of an artifact that can leak.

github.com/JadenRazo/sre-reference-app

### Draft 3: Numbered build-log list

8 things I built into a public SRE reference app this week:

1. ECS Fargate service that survives a 1-task termination in 78 seconds, end to end (kill at T+0, steady state at T+78s).
2. ALB target group with deregistration_delay = 30, not the AWS default of 300. The single highest-leverage setting for SLO survival during deploys and chaos.
3. Multi-window multi-burn-rate (MWMBR) alarms sized per Google SRE Workbook Table 5-1: 14.4x fast-burn over 5m/1h, 6x slow-burn over 30m/6h.
4. 0 AWS credentials anywhere thanks to GitHub OIDC. No access keys in the repo, in Secrets, or on the runner.
5. iam:PassRole scoped to two specific task role ARNs and conditioned on iam:PassedToService=ecs-tasks.amazonaws.com so a compromised deploy role cannot hand task roles to a Lambda.
6. Structured JSON logs with request_id, duration_ms, remote_addr. One log format per service, gunicorn access log disabled to avoid duplicates.
7. Chaos via aws ecs stop-task because AWS FIS hit SubscriptionRequiredException on a new account. Same blast radius, $0 cost.
8. Measured 4.46% error rate during chaos vs 4.83% baseline. The chaos was invisible to the SLO.

github.com/JadenRazo/sre-reference-app
