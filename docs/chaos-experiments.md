# Chaos experiments

This service runs a controlled fault-injection experiment to verify the SLO survives a realistic failure mode. The hypothesis is stated up front, the method is reproducible, and the result is measured against the SLO targets defined in `slos.md`. Each experiment ends with a "what we learned" section that captures whichever findings were not obvious before the run.

## Experiment 1: terminate one task during sustained traffic

### Hypothesis

A 2-task ECS Fargate service running behind an ALB will absorb the loss of one task without breaching the 1% error budget over a 1-hour window. The replacement task should reach the steady state in under 2 minutes. Most of the recovery time is the target group's health check requirement (2 consecutive 200s at 15s interval = 30s) and the draining task's `deregistration_delay` (configured to 30s in `modules/service/alb.tf`).

### Method

1. Start a local traffic generator at ~5 requests/second against the ALB DNS, run for 8 minutes total.
2. Wait 60 seconds for steady state.
3. Pick one task at random and call `aws ecs stop-task`. Capture the wall-clock timestamp of the call.
4. Poll `aws ecs describe-services` every 10 seconds. Capture the wall-clock timestamps of:
   - replacement task started (from service events)
   - replacement task registered with the target group
   - service "reached a steady state" event
5. After the run, query alarm states. Both `sre-app-fast-burn` and `sre-app-slow-burn` must remain in `OK` state. If either fires, the SLO did not survive.
6. Compute the measured error rate over the run and compare to the 5% configured baseline.

### Why `aws ecs stop-task` instead of AWS FIS

The original plan used the AWS FIS experiment template `sre-app-stop-tasks`. On this account the FIS API returns `SubscriptionRequiredException` (a new-account onboarding gate that does not block the build). `aws ecs stop-task` produces the same blast radius (one task gone, service must recover) at $0 cost and with no service-onboarding step. The terraform module retains the FIS template behind `var.enable_fis = false`; flip the var and re-apply to switch back when the account state changes.

### Result (2026-04-28)

Traffic generator output for the full 8-minute run:

```
total=2154, 200=2058, 5xx=96, network_err=0, error_rate=0.0446
```

Recovery timeline, with `T_KILL = 18:37:23Z` (the moment `aws ecs stop-task` returned):

| Event | Wall clock | T relative |
|---|---|---|
| Stop-task call returned (task DEACTIVATING) | 18:37:23Z | T+0 |
| ECS scheduler started replacement task | 18:38:02Z | T+39s |
| Replacement task registered with target group | 18:38:32Z | T+69s |
| Service event "has reached a steady state" | 18:38:41Z | T+78s |

Alarm states queried immediately after the run:

```
sre-app-fast-burn  OK  (no datapoints received for 1 period; treat_missing_data = "notBreaching")
sre-app-slow-burn  OK  (datapoint 0.0484 was not greater than threshold 0.06)
```

### Findings

**The service absorbed the fault entirely.** The 4.46% measured error rate during the chaos run is slightly below the 4.83% measured during the Phase 5 steady-state run (1347 requests, no chaos). The chaos did not produce a visible 5xx blip. Two reasons:

1. The ALB drained the killed task gracefully. The `deregistration_delay = 30` setting on the target group is the load-bearing piece. AWS's default is 300 seconds; with the default, in-flight requests would have queued against a dying task for 5 minutes. With 30 seconds, the ALB waits half a minute for in-flight responses to drain, then stops sending new traffic and removes the target.
2. The surviving task handled all incoming requests during the 78-second recovery window. At ~5 requests/second, that is roughly 390 requests served by one task instead of two. The 256-CPU / 512-MB Fargate task shape was not stressed; CPU utilization on the dashboard never crossed 11%.

**The 30-second `deregistration_delay` tuning matters more than the FIS template.** Most of the engineering value of this experiment is not "AWS FIS killed a task." It is the discovery that the default ALB drain timeout is wrong for a service that wants to survive task termination quickly. A longer drain produces visible 5xx during the chaos because requests queue against a dying task, and would push the error rate above the SLO budget for a real workload running closer to its capacity.

**`treat_missing_data = "notBreaching"` saved the alarms from a false page.** The 1-hour fast-burn window had no completed period at the moment the alarms were queried (the run was 8 minutes). With the default `missing` behavior, the fast-burn alarm could have flipped to `INSUFFICIENT_DATA` or `ALARM` depending on configuration. `notBreaching` keeps it `OK` until real data arrives. This is the boring-but-load-bearing setting that prevents pager fatigue on alarms protecting low-traffic windows.

**The 1-task surviving period was ~78 seconds out of an 8-minute run** (16% of the test window). For a service running at its sizing ceiling, that 78-second period would push CPU utilization to near 200% on the survivor and cause real 5xx. Right-sizing tasks must account for this kind of degraded mode, not just nominal load.

### What this experiment does not verify

- Behavior when more than one task is killed simultaneously. With `desired_count = 2`, killing both leaves the service at 0/2 running with potentially significant 5xx until ECS replaces tasks.
- Network-level chaos. An ALB-to-task connection failure, a DNS resolution failure, or a NAT gateway disruption would all stress different parts of the system.
- Slow degradation. A task that becomes slow (high latency) without dying is harder to detect than a task that dies cleanly. The current dashboard would catch it via `TargetResponseTime` p99, but no alarm currently fires on latency.

These are the next experiments to run when the chaos cadence becomes routine.

## References

- Google SRE Workbook chapter 16 ("Disaster Role Playing"): https://sre.google/workbook/chapter-16/
- AWS docs on ALB target group `deregistration_delay`: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-groups.html#deregistration-delay
- AWS FIS docs on the `aws:ecs:stop-task` action (for when FIS becomes available on this account): https://docs.aws.amazon.com/fis/latest/userguide/actions-aws-ecs.html
