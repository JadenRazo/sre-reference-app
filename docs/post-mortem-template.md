# Post-mortem template

Filled in after every SEV-2 or higher incident. Each section explains what to write and shows a worked example using the Phase 6 chaos run (one ECS task terminated, recovery 78s, no SLO breach). Voice: third person, past tense, blameless. Actions attach to roles ("the on-call engineer," "the ECS scheduler," "the ALB"), never to individuals.

## Header block

```
# Post-mortem: <incident title>

| Field | Value |
|---|---|
| Date | YYYY-MM-DD |
| Duration | <wall-clock from first symptom to all-clear> |
| Severity | SEV-2 |
| Owner | <role, e.g. "SRE on-call rotation"> |
| Status | Draft / In review / Accepted |
```

### Worked example

# Post-mortem: Single-task termination during sustained traffic

| Field | Value |
|---|---|
| Date | 2026-04-28 |
| Duration | 78 seconds (T+0 stop-task to steady state) |
| Severity | SEV-3 (controlled chaos run, no customer impact) |
| Owner | SRE on-call rotation |
| Status | Accepted |

## Summary

Two or three sentences. What happened, customer-visible impact, how it resolved.

### Worked example

A controlled chaos experiment terminated one of two ECS Fargate tasks at 18:37:23Z while a local generator drove ~5 requests per second against the ALB. The service ran on a single task for 78 seconds before the replacement reached steady state. No SLO breach occurred and neither burn-rate alarm fired; measured error rate over the 8-minute run was 4.46%, below the 4.83% Phase 5 baseline.

## Timeline (UTC)

Timestamped bullets, one line each, past tense. Include the alert that paged, first hypothesis, ownership transfers, and the all-clear.

### Worked example

- 18:36:23Z: Traffic generator started against the ALB at ~5 requests/second, planned 8 minutes.
- 18:37:23Z (T+0): The on-call engineer ran `aws ecs stop-task` against one of two running tasks. The task entered DEACTIVATING; the ALB began draining it under the configured 30-second `deregistration_delay`.
- 18:38:02Z (T+39s): ECS scheduler started a replacement in PROVISIONING.
- 18:38:32Z (T+69s): Replacement registered with the target group after two health checks (15s interval, 2-check threshold).
- 18:38:41Z (T+78s): ECS emitted "has reached a steady state" with 2/2 running.
- 18:44:23Z: Generator stopped. Final counters: 2154 total, 96 5xx, 0 network errors, error rate 0.0446.
- 18:45:00Z: The on-call engineer queried alarms. `sre-app-fast-burn` reported `OK` (notBreaching, no completed 1-hour datapoint). `sre-app-slow-burn` reported `OK` (datapoint 0.0484 below 0.06 threshold).

## Impact

Concrete numbers only. Affected requests, error rate elevation above baseline, customer-visible duration, SLO budget consumed. If impact was zero, prove it with the math.

### Worked example

- Requests served during the 8-minute run: 2154.
- 5xx responses: 96 (synthetic 5xx from the 5% baseline; no chaos-induced 5xx observed).
- Measured error rate: 4.46%, below the 4.83% Phase 5 baseline.
- SLO budget consumed by the chaos itself: ~0%. No error rate elevation above the synthetic baseline.
- Single-task period: 78 seconds (16% of the test window). Surviving task CPU peaked at 11%.

## Root cause

Direct attribution to a system or class of failure. The "5 whys" pattern is fine, but stop at the systemic cause. Name the system that allowed or absorbed the failure.

### Worked example

The trigger was a deliberate `aws ecs stop-task` call from a planned chaos experiment. Three systemic factors absorbed the fault:

1. The ALB target group ran with `deregistration_delay = 30` (AWS default is 300). In-flight requests drained in 30 seconds rather than queueing for 5 minutes against a deactivating target.
2. `desired_count = 2`. The surviving 256-CPU / 512-MB Fargate task absorbed full traffic during the 78-second window with peak CPU at 11%.
3. ECS restarted the replacement in 39 seconds; the ALB completed health checks in another 30 seconds. Both within the hypothesis in `chaos-experiments.md`.

The fault was absorbed by design, not by chance.

## What went well

Three to five bullets. Things that worked because someone built them to. Cite the specific system or setting.

### Worked example

- The 30-second `deregistration_delay` did the load-bearing work. With the AWS default of 300 seconds, in-flight requests would have queued against a dying task for 5 minutes.
- ECS automatic replacement matched the hypothesis: T+39s start, T+69s registered, T+78s steady state (predicted under 2 minutes).
- The CloudWatch dashboard surfaced 5xx by target group, request count, response time p99, and CPU per task on one screen.
- `treat_missing_data = "notBreaching"` prevented a false page when no completed 1-hour datapoint yet existed for the fast-burn alarm.

## What went wrong

Three to five bullets. Each is a system or process gap. Even a clean run usually has at least one. Talk about what the system or process did, not who.

### Worked example

- The experiment ran against a production-shape environment with no formal pre-approval gate. A real customer-facing change should require peer review and a written runbook entry before invoking `stop-task`.
- No alarm fires on `TargetResponseTime` p99. A task that becomes slow without dying would go undetected until responses timed out into 5xx.
- A runbook for "ECS task terminated unexpectedly" did not exist. The on-call engineer reasoned from first principles via `chaos-experiments.md`; a different on-call would have had to read four sources.
- The `aws ecs stop-task` substitution for AWS FIS (FIS returned `SubscriptionRequiredException`) was correct but not pre-documented; the rationale was added to `chaos-experiments.md` after the run.

## Where we got lucky

One to three bullets. Things that helped but were not by design. Convert luck into design via action items.

### Worked example

- The 2-task service had headroom because configured load was ~5 requests/second. If the survivor had been at 80% CPU, the 78-second window would have pushed it past saturation. Right-sizing must account for degraded mode, not nominal mode.
- The chaos ran during a low-traffic window. A real service at peak would see a different recovery profile, particularly if connection-level draining became the bottleneck.

## Action items

One row per action. Single owner role. Single deadline. Track status until the post-mortem is Accepted.

| Action | Owner role | Due | Status |
|---|---|---|---|
| Add CloudWatch alarm on `TargetResponseTime` p99 > 100ms for 5 min; route to the burn-rate SNS topic | terraform-architect | 2026-05-12 | Open |
| Write runbook "ECS task terminated unexpectedly" covering diagnosis steps used here | technical-writer | 2026-05-05 | Open |
| Add chaos-experiment pre-approval checklist to `docs/chaos-experiments.md` (peer review, runbook, rollback plan) | SRE on-call rotation | 2026-05-05 | Open |
| Follow-up experiment: terminate one task with the survivor at 70% CPU (degraded-mode load test) | SRE on-call rotation | 2026-05-26 | Open |
| Document the FIS-vs-stop-task substitution in the chaos plan up front, not after the fact | technical-writer | 2026-05-05 | Done |

## Glossary and links

- `docs/slos.md`: 99% availability SLO, 14.4x fast-burn and 6x slow-burn thresholds.
- `docs/chaos-experiments.md`: hypothesis, method, and result referenced here.
- `docs/runbooks/`: link the specific runbook page, not the index.
- AWS ALB `deregistration_delay`: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-groups.html#deregistration-delay

## Footer

This post-mortem is blameless. Actions pin to roles and systems, not individuals. The goal is to close systemic gaps, not assign fault. Format follows Google SRE book, chapter 15, "Postmortem Culture: Learning from Failure" (https://sre.google/sre-book/postmortem-culture/).
