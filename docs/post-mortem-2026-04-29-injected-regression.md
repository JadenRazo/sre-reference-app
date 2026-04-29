# Post-mortem: Injected error-rate regression on sre-app

> **Format:** GameDay-style. The hypothesis, method, root-cause framing, and
> action items were written **before** the run. The timeline, impact numbers,
> and section 7's hypothesis-vs-result analysis are filled in **after** the
> run from the emitted `regression-timeline.json` and from CloudWatch
> `GetMetricStatistics` queries against the ALB metrics. The hypothesis text
> in section 2 is left intact deliberately — its disagreement with what
> actually happened is the load-bearing finding of the experiment.
>
> **Status:** Executed and reviewed. Source data: `regression-timeline.json`
> (timestamps from the script) and CloudWatch `AWS/ApplicationELB`
> `RequestCount` / `HTTPCode_Target_5XX_Count` / `HTTPCode_Target_2XX_Count`
> for the window `2026-04-29T07:39:00Z` to `2026-04-29T07:47:00Z` at
> 60-second resolution.

| Field | Value |
|---|---|
| Date | 2026-04-29 |
| Duration (T_INJECT to T_ROLLBACK) | 6 minutes 24 seconds |
| Duration (T_INJECT to derived T_ALL_CLEAR) | 1 hour 6 minutes 24 seconds |
| Severity | SEV-3 (controlled regression run, no customer impact) |
| Owner | SRE on-call rotation |
| Status | Executed; reviewed |

## 1. Summary

A controlled regression experiment raised `ERROR_RATE` from 0.05 to 0.30 on
the sre-app ECS service via a new task-definition revision while a local
generator drove approximately 5 requests per second through the ALB. The goal
was to verify that the multi-window burn-rate alarm wired in
`infra/modules/observability/alarms.tf` actually pages within its documented
budget window, and that the documented rollback procedure in
`runbooks/high-latency.md` section 4.2 brings the service back to baseline
without further intervention. The fast-burn alarm fired at T+3 minutes 5
seconds, *much faster than the pre-registered hypothesis predicted*. The
on-call rolled back via `update-service` to the prior revision; the service
returned to the 5 percent baseline error rate inside two minutes of
`services-stable`. No customer impact (the experiment ran against a stack
with no real users; the generator was the only client). Total elapsed time
from injection to rollback: 6 minutes 24 seconds. The experiment's biggest
finding was a learning about the alarm itself, not the service: see section 7.

## 2. Hypothesis

This is the experiment's pre-registered hypothesis, recorded before any
keystroke went into the AWS API. It is not edited after the run; section 7
records what was actually observed and how it agreed with or deviated from
the hypothesis.

1. **Detection by dashboard:** The CloudWatch dashboard's `5xx count` widget
   surfaces the regression within 2 minutes of `T_INJECT`, because the ALB
   emits `HTTPCode_Target_5XX_Count` at a 1-minute granularity and the
   dashboard refresh is 60 seconds.
2. **Detection by alarm:** The fast-burn alarm
   (`sre-app-fast-burn`, 1-hour window, threshold `0.144`) transitions from
   `OK` to `ALARM` between 60 and 70 minutes after `T_INJECT`. The lower bound
   is the metric window itself; the upper bound is the metric-emission lag
   plus alarm-evaluation lag (CloudWatch alarms evaluate every minute and
   require a *complete* 1-hour datapoint at this period setting). The
   slow-burn alarm (`sre-app-slow-burn`, 6-hour window, threshold `0.06`)
   does **not** fire within the experiment window because no complete 6-hour
   datapoint elapses.
3. **Recovery:** Once the rollback step (`update-service` to the prior task
   definition revision) emits the "service has reached a steady state" event,
   the dashboard returns to baseline within 2 minutes. The fast-burn alarm
   returns to `OK` within 60 to 70 minutes after rollback (same window logic,
   in reverse). `treat_missing_data = "notBreaching"` keeps the alarm in `OK`
   even before that window completes if the metric falls back below threshold.
4. **No collateral:** Neither the slow-burn alarm, nor any latency-related
   metric, nor any non-target metric (CPU, memory, task count) crosses any
   threshold. The 256-CPU / 512-MB Fargate task shape has the headroom to
   serve 5 rps at a 30 percent error rate with the same CPU envelope as the
   no-error baseline (Phase 5 measured peak at 11 percent during chaos).

## 3. Timeline (UTC)

Filled in from `regression-timeline.json` and CloudWatch metric queries.

- **2026-04-29T07:36:10Z**: Pre-flight check completed. Service running on
  `arn:aws:ecs:us-west-2:569239324174:task-definition/sre-app:5`. Both
  burn-rate alarms in `OK`. ALB DNS
  `sre-app-alb-1243008614.us-west-2.elb.amazonaws.com` resolvable.
- **2026-04-29T07:39:48Z (T+0)**: `update-service` to regression task
  definition `arn:aws:ecs:us-west-2:569239324174:task-definition/sre-app:6`
  (`ERROR_RATE = 0.30`) reached steady state. Traffic generator started at
  5 rps.
- **2026-04-29T07:40:00Z (T+12s)**: First CloudWatch 1-minute aggregation
  bucket containing regression traffic. ALB recorded 259 requests, 65 5xx,
  194 2xx in the bucket — a 25 percent error rate, plainly above the 5
  percent baseline. The dashboard's `5xx count` widget would have surfaced
  this on its next 60-second refresh.
- **2026-04-29T07:42:53Z (T+3m05s)**: `sre-app-fast-burn` transitioned
  `OK -> ALARM`. SNS topic `arn:aws:sns:us-west-2:569239324174:sre-app-slo-alerts`
  fanned out to the email subscription. Wall-clock from injection to first
  page: 3 minutes 5 seconds. **This is much faster than the pre-registered
  60-to-70-minute hypothesis** — see section 7.
- **2026-04-29T07:43:00Z (T+3m12s)**: Reading the alarm's most recent
  evaluation: `m1 = 209 5xx`, `m2 = 840 RequestCount` for the in-progress
  `[07:00, 08:00)` bucket; ratio 0.249 against threshold 0.144.
- **2026-04-29T07:46:12Z (T+6m24s)**: `update-service` to the pre-state
  revision `sre-app:5` reached steady state. Traffic generator stopped.
  Total wall-clock from page to rollback: 3 minutes 19 seconds.
- **2026-04-29T07:46:12Z (derived)**: `T_ALL_CLEAR` derived as
  `T_ROLLBACK + 60 minutes = 2026-04-29T08:46:12Z` rather than observed,
  because the script ran with `--skip-all-clear-wait` to avoid keeping the
  stack billable for an additional hour. The fast-burn alarm trails the
  metric by exactly its 1-hour window: even after the metric drops below
  threshold (which it does immediately when the service returns to the 5
  percent baseline), the rolling 1-hour aggregate still contains the
  regression's 5xx and stays above 0.144 until those data points roll out.
- **Slow-burn alarm**: held `OK` throughout. The 6-hour window had no
  complete datapoint over the experiment window, and the partial-period
  ratio against the slow-burn 0.06 threshold also stayed below threshold
  because of how `IF(m2 > 0, m1 / m2, 0)` smooths over the bucket.

## 4. Impact

CloudWatch `AWS/ApplicationELB` metrics for the experiment window
`07:39:00Z` to `07:47:00Z`, at 60-second resolution:

| Minute (UTC) | RequestCount | 5xx | 2xx | Per-min error rate |
|---|---:|---:|---:|---:|
| 07:39 (partial, mid-rollout) | 52 | 18 | 34 | 0.346 |
| 07:40 | 259 | 65 | 194 | 0.251 |
| 07:41 | 264 | 76 | 188 | 0.288 |
| 07:42 | 265 | 74 | 191 | 0.279 |
| 07:43 (alarm fired at T+3m05s; rollback rolling) | 260 | 69 | 191 | 0.265 |
| 07:44 (rollback rolling) | 263 | 56 | 207 | 0.213 |
| 07:45 (rollback steady-state imminent) | 264 | 14 | 250 | 0.053 |
| 07:46 (rollback complete; baseline restored) | 54 | 1 | 53 | 0.019 |
| **Total** | **1,681** | **373** | **1,308** | **0.222** |

- Total requests during experiment window: **1,681**.
- 5xx during experiment window: **373**.
- Measured error rate: **22.2 percent** (lower than the 30 percent
  injection because the window includes the rollback transition and
  ~90 seconds of post-rollback baseline traffic).
- Errors above baseline (attributable to the regression):
  `373 - (1681 * 0.05) = 373 - 84 = 289`.
- Time spent at an error rate above the 0.144 fast-burn threshold:
  approximately **5 minutes** (07:40-07:45 inclusive at 60-second
  granularity).
- SLO budget consumption (math from `docs/slos.md` section 1, with the
  100-req/min reference traffic level): a 30-day budget allows 43,200
  failures. The 289 above-baseline errors consume **0.67 percent** of
  the 30-day budget. At higher real-world traffic levels the absolute
  error count scales, but the percentage of budget consumed is roughly
  the same because the regression is bounded in time, not in rate.
- Customer impact: zero. The experiment ran against a stack with no real
  traffic; the generator was the only client. This number must be
  replaced for a real-incident run of the template.

## 5. Root cause

Direct attribution. The "5 whys" pattern is fine, but stop at the
systemic cause. Name the system that allowed or absorbed the failure.

The trigger was a deliberate `ERROR_RATE` bump from 0.05 to 0.30, applied
via task-definition revision `sre-app:6` and rolled out by
`update-service`. This is by construction; the interesting question is
what surfaced it and how fast.

1. The regression became visible on the dashboard at the first 1-minute
   aggregation boundary after injection, because the ALB emits
   `HTTPCode_Target_5XX_Count` and `RequestCount` at 1-minute granularity
   and the dashboard widget aggregates with a 60-second period.
2. The fast-burn alarm fired in 3 minutes 5 seconds. The mechanism is
   *not* what the hypothesis assumed (a complete 1-hour datapoint).
   CloudWatch alarms with `metric_query` and `period = 3600` evaluate the
   expression on every alarm evaluation interval (default 60s) against the
   *most recent in-progress period bucket*. With no traffic in the
   `[07:00, 08:00)` bucket before T_INJECT and 5 rps of regression
   traffic after, the bucket's running ratio crossed 0.144 within ~3
   minutes — well before the bucket finalized at 08:00. This is a
   correct-by-design CloudWatch behavior, but the project's hypothesis
   (and `docs/slos.md` section 3) treated the 1-hour window as a *minimum*
   detection latency. It is in fact an *upper bound on the smoothing
   window* that gets shorter when prior traffic in the bucket is sparse.
3. The rollback returned the service to baseline because
   `lifecycle.ignore_changes = [task_definition, desired_count]` on the
   ECS service in `infra/modules/service/ecs.tf` lets the deploy path
   register new revisions without `terraform apply` reverting them. The
   prior revision (`sre-app:5`) was still resolvable by ARN and could be
   re-pinned in one CLI call.

The fault was injected by the experiment, surfaced by the partial-period
behavior of the metric expression, and absorbed by the rollback path.

## 6. What went well

- **The alarm fired and paged.** The end-to-end path (alarm transition →
  SNS → email subscription) worked without intervention. No false page
  during the no-error baseline ahead of injection. No flapping after
  rollback.
- **Detection was much faster than the pre-registered worst case.** 3
  minutes 5 seconds is well inside any reasonable on-call expectation,
  and is a strict improvement over the hypothesis's 60-to-70-minute
  budget. See section 7 for why this is a finding even though it sounds
  like a positive.
- **The rollback procedure in `runbooks/high-latency.md` section 4.2 was
  copy-pasted into the script with no edits.** The runbook is correct as
  written. The script's `--rollback-only` recovery mode also exercises
  exactly the same path.
- **`treat_missing_data = "notBreaching"` kept the alarm quiet during
  the rollback window.** A naive missing-data policy would have flapped
  the alarm to `INSUFFICIENT_DATA` while a partial 1-hour bucket
  re-evaluated.
- **The structured JSON logs at `/ecs/sre-app` segregated revisions
  cleanly via the `version` field.** A CloudWatch Logs Insights query
  ```
  fields @timestamp, status, request_id, duration_ms, version
  | filter status >= 500
  | stats count() by version, bin(1m)
  ```
  separates regression-revision 5xx from baseline-revision 5xx in seconds.

## 7. What went wrong

This section captures both pre-registered concerns and post-run
discoveries.

### Pre-registered

- **No latency burn-rate alarm fires.** `TargetResponseTime` p99 is on
  the dashboard but unalarmed. A regression that increased latency
  without increasing error rate would not page at all. Same root cause
  as the Phase 6 chaos finding; the action item is unchanged.
- **The rollback step is a CLI invocation.** There is no equivalent
  `gh workflow run rollback.yml` or other pull-only path. An on-call
  engineer without local AWS credentials cannot roll back. Tracked.

### Post-run (new)

- **The hypothesis was wrong about alarm latency.** The pre-registered
  hypothesis predicted `OK -> ALARM` in 60 to 70 minutes; the actual
  transition was at 3 minutes 5 seconds. The error in the hypothesis was
  treating CloudWatch's `period = 3600` as "the alarm requires a complete
  1-hour datapoint to fire". It does not. With metric_query and a
  partially-filled period bucket, the alarm fires as soon as the running
  m1/m2 ratio crosses threshold, regardless of how much of the period
  has elapsed. This means:
  - **For a service with high baseline traffic in the bucket at the time
    of injection, the regression's contribution is diluted by the prior
    healthy traffic.** Detection latency under that condition is closer
    to the 60-minute upper bound, which is what the hypothesis assumed.
    But it is not a *minimum*; it is a *maximum, conditional on prior
    bucket state*.
  - **`docs/slos.md` section 3 should clarify this.** The documented
    "1-hour window" describes the *smoothing horizon*, not the *minimum
    detection time*.
  - **For real production services that run with continuous traffic,
    the effective detection latency depends on the ratio of regression
    traffic to prior bucket traffic.** A regression that doubles the
    baseline error rate during peak hours fires faster than the same
    regression during a quiet hour. This is worth documenting in the
    runbook.
- **The script's traffic-generator counter was lost on kill.** The
  background subshell wrote its counters via a final `printf` after the
  loop exited normally. When the main script killed the subshell on
  alarm-fire, the printf never ran and the counter file was empty.
  CloudWatch metrics filled the gap (numbers in section 4 are from the
  ALB itself, not the generator). The script should be updated to use
  `trap` with EXIT/INT/TERM to flush the counter on any exit path.
- **The dashboard does not surface the actual alarm threshold.** A
  reader of the dashboard cannot tell whether a 25 percent error rate is
  "above the alarm threshold" without consulting `docs/slos.md`. Adding
  a horizontal annotation line at 0.144 on the error-ratio widget would
  make the dashboard self-explanatory.

## 8. Where we got lucky

- **The 0.30 error rate is not realistic for a production regression.**
  A real bad deploy more typically produces 1-5 percent elevation. With a
  prior bucket at substantial baseline traffic, that elevation could push
  detection to several hours rather than 3 minutes. This experiment did
  not stress that case. (Action item below.)
- **The rollback target (the prior task definition revision) was still
  resolvable.** ECS keeps revisions around indefinitely by default; if a
  cleanup policy were in place that pruned old revisions, the rollback
  ARN might not exist.
- **Traffic was synthetic and uniform.** Real traffic is bursty; a
  regression that interacts with traffic patterns (e.g. a memory leak
  that surfaces under load) would not show up cleanly in a 5-rps
  experiment.

## 9. Action items

| Action | Owner role | Due | Status |
|---|---|---|---|
| Update `docs/slos.md` section 3 to clarify that the 1-hour metric window is a smoothing horizon, not a minimum detection latency. Document the dependency on prior bucket state | technical-writer | 2026-05-06 | Open |
| Add CloudWatch alarm on `TargetResponseTime` p99 above 200 ms for 5 minutes; route to the burn-rate SNS topic | terraform-architect | 2026-05-13 | Open |
| Add a "fast 5xx surge" alarm: `HTTPCode_Target_5XX_Count > 30 over 5 min`, ticket-only severity (not page). Bridges the dashboard / alarm gap surfaced in the original section-7 hypothesis | terraform-architect | 2026-05-13 | Open |
| Add a horizontal threshold annotation at 0.144 to the error-ratio dashboard widget so the dashboard is self-explanatory | terraform-architect | 2026-05-13 | Open |
| Fix the traffic-generator counter loss in `scripts/inject-regression.sh`: `trap` on EXIT to flush the counter file regardless of exit path | devops-pipeline | 2026-05-06 | Done (shipped in same commit as this post-mortem) |
| Add a `gh workflow run rollback.yml` workflow that takes a target revision argument so on-call can roll back without local AWS credentials | devops-pipeline | 2026-05-13 | Open |
| Re-run this experiment with `--error-rate 0.10` against a 30-minute pre-warm of baseline traffic. The pre-warm exercises the "high baseline traffic in bucket at injection" case and tests whether detection latency stretches toward the upper bound | SRE on-call rotation | 2026-05-20 | Open |

## 10. Glossary and links

- `regression-timeline.json`: Source of truth for the timeline section.
  Emitted by `scripts/inject-regression.sh`. Not committed by default
  because it carries a specific account ID; see the script's `--out` flag.
- `docs/slos.md`: SLO target, burn-rate derivation, why 14.4x and 6x.
  Pending update per section 9.
- `docs/chaos-experiments.md`: Phase 6 single-task termination (precedent
  for this run's GameDay format).
- `runbooks/high-latency.md`: Source of section 4.2 rollback procedure.
- `scripts/inject-regression.sh`: Automation that drove the experiment.
- Google SRE Workbook chapter 16, "Disaster Role Playing":
  https://sre.google/workbook/chapter-16/
- Google SRE book chapter 15, "Postmortem Culture":
  https://sre.google/sre-book/postmortem-culture/
- AWS docs on CloudWatch alarm evaluation with metric math and partial
  periods:
  https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html

## Footer

This post-mortem is blameless. Actions pin to roles and systems, not
individuals. The goal is to close systemic gaps, not assign fault. The
hypothesis-versus-result gap surfaced in section 7 is the most valuable
finding of the run; preserving the original hypothesis text in section 2
is what makes that comparison legible. Format follows Google SRE book
chapter 15.
