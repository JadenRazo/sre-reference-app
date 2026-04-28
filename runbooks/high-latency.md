# Runbook: high latency or elevated 5xx on sre-app

You are on-call. The fast-burn alarm fired or a user said the app is slow. Work through the sections in order. Commands are read-only until section 4.

## 1. When to use this runbook

Use this runbook when any of the following is true:

- CloudWatch alarm `sre-app-fast-burn` is in `ALARM` state (1-hour window, 14.4% error rate threshold, about 2 days to budget exhaustion).
- CloudWatch alarm `sre-app-slow-burn` is in `ALARM` state (6-hour window, 6% threshold, about 5 days to exhaustion).
- A user reports the app is slow or returning errors and no alarm has fired yet.
- Synthetic checks against the ALB DNS return non-200 responses or response times above 1s.

Do not use this runbook for AWS region-wide outages, ALB-level failures, or VPC and NAT issues. See section 6.

## 2. First 60 seconds (read-only triage)

Open three tabs. Do not change anything yet.

1. The dashboard: `https://us-west-2.console.aws.amazon.com/cloudwatch/home?region=us-west-2#dashboards:name=sre-app-dashboard`. Look at, in this order:
   - **5xx counts** widget. If the count is above 10/min sustained for 5 minutes, an outage is in progress.
   - **TargetResponseTime p99** widget. Steady state is under 100ms. p99 above 500ms means latency is the symptom even if 5xx counts are normal.
   - **Target health** widget. Healthy host count below 2 means a task is unhealthy or replaced.
   - **ECS RunningTaskCount**. Steady state is 2. Below 2 means ECS is replacing a task; below desired count for more than 3 minutes is a problem.

2. The ECS service page: `https://us-west-2.console.aws.amazon.com/ecs/v2/clusters/sre-app-cluster/services/sre-app/events`. Read the last 5 events. ECS posts plain-English events when it stops, replaces, or fails to place a task.

3. A terminal. Confirm alarm states with one command:
   ```
   aws cloudwatch describe-alarms \
     --alarm-names sre-app-fast-burn sre-app-slow-burn \
     --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Reason:StateReason}'
   ```

If 5xx counts are flat and p99 is normal but a user is complaining, the user may be hitting a different system. Confirm they are hitting the ALB DNS before continuing.

## 3. Common causes (ranked by frequency)

Most incidents on this service fall into one of these five buckets. Check each one before escalating.

### 3.1 Task crashing or unhealthy

The most common cause. ECS RunningTaskCount drops below desired_count of 2. The ALB pulls the bad target, and the surviving task carries full load until a replacement registers (about 78 seconds in the Phase 6 chaos test).

To confirm:
```
aws ecs describe-services --cluster sre-app-cluster \
  --services sre-app --query 'services[0].events[0:5]'
```
Look for "task ... stopped" or "service ... was unable to place a task" entries.

### 3.2 One task hot, one cold

p99 latency spikes but error rate is fine. One task is serving most traffic because of ALB routing skew or because a recent deploy left one task with a warmer cache.

To confirm: open the ECS console, click each task, view per-task CPU. A 3x spread between the two tasks is the signal.

### 3.3 Bad deploy

A recent task definition revision introduced a regression. Check deploy time against alarm time. If a CI run completed in the last hour, this is the first hypothesis.

To confirm:
```
aws ecs describe-services --cluster sre-app-cluster \
  --services sre-app --query 'services[0].deployments'
```
Roll back via section 4.2.

### 3.4 Upstream dependency slow

TargetResponseTime is elevated but error rate is normal. The app is healthy and waiting on something. This service makes no real upstream calls today, but if you have added one, this is where it shows up.

To confirm: read CloudWatch log group `/ecs/sre-app`. Filter for log lines with `duration_ms` above 200. Slow lines clustered around one downstream URL identify the dependency.

### 3.5 Cold ALB target

A freshly registered task has not had its TLS sessions warmed and is slow on first requests. Usually transient and resolves in under 60 seconds. If TargetResponseTime spikes right after a deploy and recovers on its own, this was the cause; no action needed.

## 4. Mitigation steps (in escalation order)

Start with the least disruptive option. Each step assumes the previous one did not resolve the issue.

### 4.1 Force a cycle of all tasks

Safe first move when a task is in a bad state but ECS has not noticed:
```
aws ecs update-service --cluster sre-app-cluster \
  --service sre-app --force-new-deployment

aws ecs wait services-stable --cluster sre-app-cluster \
  --services sre-app
```
This replaces both tasks under the rolling deploy policy. Expect 2 to 3 minutes to stable.

### 4.2 Roll back to a known-good revision

If the cause is a bad deploy, roll back. List the last 5 revisions:
```
aws ecs list-task-definitions --family-prefix sre-app \
  --sort DESC --max-items 5
```
Then roll back:
```
aws ecs update-service --cluster sre-app-cluster \
  --service sre-app \
  --task-definition sre-app:<previous-revision>

aws ecs wait services-stable --cluster sre-app-cluster \
  --services sre-app
```

### 4.3 Scale up

If both tasks are healthy but CPU is pinned, double capacity:
```
aws ecs update-service --cluster sre-app-cluster \
  --service sre-app --desired-count 4
```
Set this back to 2 in section 5 once the incident clears.

### 4.4 Upstream is at fault

If the cause is an upstream dependency, do not page that team blindly. Open an incident channel, post the dashboard link and timestamp range, and tag the upstream owner. Capture slow log lines with their `request_id` values so the upstream team can trace them.

## 5. After resolution

1. Confirm both alarms returned to `OK`:
   ```
   aws cloudwatch describe-alarms \
     --alarm-names sre-app-fast-burn sre-app-slow-burn \
     --query 'MetricAlarms[].{Name:AlarmName,State:StateValue}'
   ```
2. If you scaled up in 4.3, scale back to 2:
   ```
   aws ecs update-service \
     --cluster sre-app-cluster \
     --service sre-app \
     --desired-count 2
   ```
3. Open `docs/post-mortem-template.md` and write the post-mortem. Fill in the timeline, the contributing factors, and the action items. Blameless voice, third person, past tense.
4. If the cause was new (not in section 3 above), add a fourth or fifth bullet there with the "to confirm" command. The next on-call inherits your work.

## 6. What this runbook does NOT cover

- AWS region-wide outages. Check `https://health.aws.amazon.com/health/status` first if multiple unrelated services are also failing.
- VPC or NAT gateway disruptions. Symptoms: tasks cannot pull images, cannot reach upstream APIs, ECS task placement fails with networking errors.
- ALB itself is unhealthy. Symptoms: the ALB DNS does not resolve, or returns 503 with `Server: awselb/2.0` regardless of target state.

These need a different runbook. This one assumes the platform is up and the app is at fault. If you are five minutes in and none of section 3 applies, stop and check whether the platform is the problem before continuing.
