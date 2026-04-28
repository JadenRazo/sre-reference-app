# SLOs and burn-rate alarms

This service runs a single availability SLO. Two CloudWatch alarms watch it: a fast-burn alarm sized to page within an hour of a serious regression, and a slow-burn alarm sized to file a ticket when the budget is bleeding out over days. The numbers below explain why those specific thresholds were chosen and what each one would catch.

## 1. The SLO

**Target: 99% of HTTP requests return a status code below 500 over a rolling 30-day window.**

The error budget is the complement:

```
error_budget = 1 - 0.99 = 0.01
```

That is 1% of requests over 30 days are allowed to fail before the SLO is breached. Translated into request counts for two example traffic levels (30 days = 43,200 minutes):

| Sustained traffic | Requests per 30 days | Failures allowed (1%) |
|---|---|---|
| 100 req/min | 4,320,000 | 43,200 |
| 1,000 req/min | 43,200,000 | 432,000 |

Those failure counts are the budget. Spend them however you want: one bad deploy that bursts 50,000 5xx in five minutes, or a slow drip of 1,440 failures per day. Once they are gone, the SLO is missed for the window.

### A note on the demo's intentional error rate

`app/main.py` injects 5xx on the `/` route at a configurable rate, defaulting to `ERROR_RATE = 0.05`:

```python
ERROR_RATE = float(os.environ.get("ERROR_RATE", "0.05"))
...
if random.random() < ERROR_RATE:
    return jsonify({"error": "synthetic 5xx"}), 500
```

5% is **5x the SLO budget**. That is intentional for the demo so the dashboards and alarms have visible signal without needing to inject chaos. A real service must run a baseline error rate well below 1%, otherwise the SLO is missed by definition before any incident occurs. Treat the 5% here as a teaching artifact, not a target.

## 2. Why two alarms

A single fixed-window error-rate alarm is either too noisy or too late. A 5-minute window at 1% threshold pages on every benign blip; a 24-hour window at 1% threshold notices the outage after the budget is already spent. The pattern this repo uses is multi-window, multi-burn-rate (MWMBR), documented in chapter 5 of the Google SRE Workbook.

The shape:

- A **fast-burn** alarm watches a short window (1 hour) at a high burn-rate multiplier. It fires when the budget is being consumed fast enough that the entire 30-day allotment would be gone in about two days. This pages the on-call.
- A **slow-burn** alarm watches a longer window (6 hours) at a lower multiplier. It fires when the budget is bleeding fast enough to deplete in about five days. This files a ticket; nobody wakes up.

Two windows reduce noise. A 1-minute traffic spike does not page because the 1-hour average smooths it out. A sustained 1-hour burn does page because the average crosses the threshold for the full window.

## 3. The math, with numbers

The burn rate is the multiplier on the error budget. A 1x burn rate means the service is failing exactly at the SLO budget rate, which would deplete the 30-day budget in 30 days. A 14.4x burn rate depletes it 14.4 times faster.

### Fast-burn: 1-hour window, 14.4x burn rate

```
threshold = (1 - SLO) * burn_rate
          = (1 - 0.99) * 14.4
          = 0.144
```

A sustained 14.4% error rate over 1 hour fires this alarm. At 14.4x:

```
30 days / 14.4 = 2.08 days to budget exhaustion
```

So when this alarm fires and the cause is not fixed, you have roughly two days before the 30-day SLO is missed. That is enough time to page, diagnose, and ship a fix without sleeping at the desk, but tight enough that the on-call cannot ignore it overnight.

Why 14.4x specifically: it is the rate at which a 1-hour averaging window detects a budget burn that would deplete the 30-day budget in about 2 days, which is the standard fast-burn pair from Google SRE Workbook Table 5-1.

### Slow-burn: 6-hour window, 6x burn rate

```
threshold = (1 - 0.99) * 6 = 0.06
```

A sustained 6% error rate over 6 hours fires this alarm. At 6x:

```
30 days / 6 = 5 days to budget exhaustion
```

The slow-burn fires before the budget is gone, but the 6-hour averaging window means a brief 6% spike will not trip it. You need 6% sustained for hours, which is the kind of slow regression a fast-burn alarm misses because no single hour is bad enough.

### The trade-off

Lowering the fast-burn multiplier from 14.4x to 7.2x would catch issues sooner (roughly 4 days to exhaustion instead of 2), but the lower threshold (7.2% sustained for 1 hour) trips on more transient incidents. Raising it to 28.8x cuts false pages but waits until the budget is being eaten in roughly a day, which leaves less response margin. The 14.4x / 6x pair is the documented sweet spot for a 30-day window and is what this repo ships.

## 4. What fires what

| Alarm | Window | Threshold | SNS action | Treat as |
|---|---|---|---|---|
| `${name_prefix}-fast-burn` | 1 hour | 14.4% error rate | email | page |
| `${name_prefix}-slow-burn` | 6 hours | 6% error rate | email | ticket |

Both alarms set `treat_missing_data = "notBreaching"`. Periods of zero traffic produce no metric data, and without that flag a missing-data state would either false-fire or false-OK. `notBreaching` keeps the alarm in `OK` until real data arrives.

In this project, "page" means "an email lands in the inbox configured on the SNS topic." In production, the same SNS topic would route to PagerDuty, Opsgenie, or whichever pager system the team uses. The alarm logic is identical; the destination changes.

## 5. Verifying the math against live data

### Phase 5 sustained-traffic run (2026-04-28, 5 minutes at ~5 req/s)

Local traffic generator:

```
total=1347, 200=1282, 5xx=65, error_rate=0.0483
```

Measured error rate **4.83%**, within ±1% of the 5% configured baseline. Variance for n=1347 with p=0.05 is `sqrt(p(1-p)/n) ≈ 0.6%`, so 4.83% is comfortably inside one standard deviation.

Alarm states queried immediately after the run:

```
sre-app-fast-burn  OK  reason: no datapoints were received for 1 period
                       and 1 missing datapoint was treated as [NonBreaching]
sre-app-slow-burn  OK  reason: 1 datapoint [0.04841402337228715
                       (28/04/26 12:18:00)] was not greater than the
                       threshold (0.06)
```

Both alarms held `OK` as designed:

- `slow-burn` saw the live error ratio (0.0484) and confirmed it sat below the 0.06 threshold. The 6-hour metric window aggregates available datapoints; with 5 minutes of traffic, the partial window already had enough signal to evaluate.
- `fast-burn` returned `notBreaching` because the 1-hour window had no completed period yet (the run was 5 minutes). `treat_missing_data = "notBreaching"` is doing exactly what it should: silence on data starvation, not false alarm.

This is the load-bearing confirmation that the SLO design holds at steady state. The 5% intentional baseline is "high-error-rate-by-design" relative to a real service but still well below either burn-rate threshold, so the alarms are quiet during normal operation and only fire when something actually breaks.

### Phase 6 chaos run (2026-04-28, `aws ecs stop-task` against one of two running tasks)

Full write-up in `chaos-experiments.md`. Numbers relevant to this doc:

- 8-minute run at ~5 req/s, 2154 total requests, 96 5xx, measured error rate **4.46%**.
- One task killed at T+76s. Service reached steady state (2/2 running) at T+154s. Recovery window was 78 seconds.
- Both alarms held `OK`. The slow-burn alarm's evaluated datapoint stayed at 0.0484, well below the 0.06 threshold. The fast-burn alarm reported `notBreaching` because the 1-hour window had no completed period over the 8-minute run.
- The chaos did not push the measured error rate above the steady-state baseline. 4.46% during chaos is in fact slightly below the 4.83% Phase 5 baseline, because the surviving task served traffic cleanly during the 78-second recovery and the ALB drained the killed task gracefully (the 30-second `deregistration_delay` setting is doing real work here, see `chaos-experiments.md` for the analysis).

This is the load-bearing finding: a single-task termination on a 2-task service did not breach the SLO. The infrastructure absorbed the fault, which is exactly what an SLO is supposed to guarantee for a fault of this size.

## 6. References

- Google SRE Workbook, chapter 5, "Alerting on SLOs": https://sre.google/workbook/alerting-on-slos/
- AWS CloudWatch metric math for burn-rate alarms: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/using-metric-math.html
- AWS docs on alarm states and missing data: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html#alarms-and-missing-data
