#!/usr/bin/env bash
#
# inject-regression.sh
# ---------------------
# Drives a controlled regression experiment against the running sre-app
# service, captures the timeline of detect-page-rollback-recover, and
# emits a JSON document suitable for filling out the post-mortem at
# docs/post-mortem-2026-04-29-injected-regression.md.
#
# Method:
#   1. Capture pre-state: current task definition revision, alarm states,
#      ALB DNS, CloudWatch dashboard URL.
#   2. Register a NEW task-definition revision identical to the current one
#      except ERROR_RATE is bumped from 0.05 -> 0.30 (configurable).
#   3. update-service to point at the regression revision.
#      Wait for service stable. Capture T_INJECT.
#   4. Drive traffic at N rps in the background for the duration.
#   5. Poll fast-burn alarm state every 60s. When it transitions to ALARM,
#      capture T_ALARM_FIRES.
#   6. Roll back: update-service to the pre-state revision.
#      Wait for service stable. Capture T_ROLLBACK.
#   7. Poll alarm state until it returns to OK. Capture T_ALL_CLEAR.
#   8. Emit a JSON timeline.
#
# Pre-reqs:
#   - terraform apply complete; ECS service stable (runningCount == desiredCount).
#   - AWS CLI v2 configured with the build-day admin user (or any role with
#     ecs:UpdateService, ecs:Register/DescribeTaskDefinition, cloudwatch:DescribeAlarms,
#     elasticloadbalancing:Describe* on the project resources).
#   - jq, curl on PATH.
#
# Cost estimate: ~$0.50-1.00 for the experiment window (75 min default)
# on top of whatever idle time the stack runs.
#
# This script is read-only on AWS account state outside the project's two
# named ECS resources; it does not touch IAM, networking, or any other
# service. It is safe to ctrl-C: the rollback step is also runnable
# standalone via:
#   scripts/inject-regression.sh --rollback-only --previous-task-def <ARN>
#
# Usage:
#   scripts/inject-regression.sh                    # 0.30 error rate, 75 min, 5 rps
#   scripts/inject-regression.sh --error-rate 0.50  # higher error rate (faster trip)
#   scripts/inject-regression.sh --duration-min 90  # longer run
#
set -euo pipefail

# --- Defaults ----------------------------------------------------------------
CLUSTER="${CLUSTER:-sre-app-cluster}"
SERVICE="${SERVICE:-sre-app}"
TASK_FAMILY="${TASK_FAMILY:-sre-app}"
FAST_BURN_ALARM="${FAST_BURN_ALARM:-sre-app-fast-burn}"
SLOW_BURN_ALARM="${SLOW_BURN_ALARM:-sre-app-slow-burn}"
REGION="${AWS_REGION:-us-west-2}"

ERROR_RATE="0.30"
DURATION_MIN="75"
TRAFFIC_RPS="5"
POLL_INTERVAL="60"
ROLLBACK_ONLY="false"
PREVIOUS_TASK_DEF=""
TIMELINE_OUT="${TIMELINE_OUT:-./regression-timeline.json}"
SKIP_ALL_CLEAR_WAIT="false"

# --- Arg parse ---------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --error-rate)       ERROR_RATE="$2"; shift 2 ;;
    --duration-min)     DURATION_MIN="$2"; shift 2 ;;
    --traffic-rps)      TRAFFIC_RPS="$2"; shift 2 ;;
    --rollback-only)    ROLLBACK_ONLY="true"; shift ;;
    --previous-task-def) PREVIOUS_TASK_DEF="$2"; shift 2 ;;
    --out)              TIMELINE_OUT="$2"; shift 2 ;;
    --skip-all-clear-wait) SKIP_ALL_CLEAR_WAIT="true"; shift ;;
    -h|--help)
      grep -E '^# ' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log()  { printf '[%s] %s\n' "$(now)" "$*" >&2; }
fail() { log "FATAL: $*"; exit 1; }

for cmd in aws jq curl; do
  command -v "$cmd" >/dev/null || fail "$cmd not on PATH"
done

# --- Rollback-only path (recovery from a failed run) -------------------------
if [[ "$ROLLBACK_ONLY" == "true" ]]; then
  [[ -n "$PREVIOUS_TASK_DEF" ]] || fail "--rollback-only requires --previous-task-def <ARN>"
  log "rolling back $SERVICE to $PREVIOUS_TASK_DEF"
  aws ecs update-service \
    --cluster "$CLUSTER" --service "$SERVICE" \
    --task-definition "$PREVIOUS_TASK_DEF" \
    --force-new-deployment \
    --region "$REGION" >/dev/null
  aws ecs wait services-stable \
    --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION"
  log "rollback complete"
  exit 0
fi

# --- Pre-flight --------------------------------------------------------------
log "pre-flight: capturing service state"

PRE_TD_ARN="$(aws ecs describe-services \
  --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" \
  --query 'services[0].taskDefinition' --output text)"
[[ -n "$PRE_TD_ARN" && "$PRE_TD_ARN" != "None" ]] || fail "service not found or unstable"
log "current task definition: $PRE_TD_ARN"

PRE_FAST_BURN_STATE="$(aws cloudwatch describe-alarms \
  --alarm-names "$FAST_BURN_ALARM" --region "$REGION" \
  --query 'MetricAlarms[0].StateValue' --output text)"
PRE_SLOW_BURN_STATE="$(aws cloudwatch describe-alarms \
  --alarm-names "$SLOW_BURN_ALARM" --region "$REGION" \
  --query 'MetricAlarms[0].StateValue' --output text)"
log "alarm pre-state: fast=$PRE_FAST_BURN_STATE slow=$PRE_SLOW_BURN_STATE"

[[ "$PRE_FAST_BURN_STATE" == "OK" ]] || fail "fast-burn alarm is $PRE_FAST_BURN_STATE; refusing to inject"

ALB_DNS="$(aws elbv2 describe-load-balancers --region "$REGION" \
  --query "LoadBalancers[?contains(LoadBalancerName, 'sre-app')].DNSName | [0]" \
  --output text)"
[[ -n "$ALB_DNS" && "$ALB_DNS" != "None" ]] || fail "ALB DNS not found"

T_PRE="$(now)"

# --- Build regression task definition ----------------------------------------
log "rendering regression task definition (ERROR_RATE=$ERROR_RATE)"
TDDIR="$(mktemp -d)"
trap 'rm -rf "$TDDIR"' EXIT

aws ecs describe-task-definition \
  --task-definition "$TASK_FAMILY" --include TAGS --region "$REGION" \
  --query taskDefinition > "$TDDIR/td.json"
TAGS_JSON="$(aws ecs describe-task-definition \
  --task-definition "$TASK_FAMILY" --include TAGS --region "$REGION" \
  --query 'tags' --output json)"

jq --arg er "$ERROR_RATE" --argjson tags "$TAGS_JSON" '
  .containerDefinitions[0].environment = (
    (.containerDefinitions[0].environment // [])
    | map(select(.name != "ERROR_RATE"))
    | . + [{"name": "ERROR_RATE", "value": $er}]
  )
  | {family, networkMode, cpu, memory, requiresCompatibilities,
     executionRoleArn, taskRoleArn, containerDefinitions}
  + (if ($tags | length) > 0 then {tags: $tags} else {} end)
' "$TDDIR/td.json" > "$TDDIR/td-regression.json"

REGRESSION_TD_ARN="$(aws ecs register-task-definition \
  --cli-input-json "file://$TDDIR/td-regression.json" --region "$REGION" \
  --query 'taskDefinition.taskDefinitionArn' --output text)"
log "registered regression revision: $REGRESSION_TD_ARN"

# --- Inject ------------------------------------------------------------------
log "injecting regression: update-service to $REGRESSION_TD_ARN"
aws ecs update-service \
  --cluster "$CLUSTER" --service "$SERVICE" \
  --task-definition "$REGRESSION_TD_ARN" \
  --force-new-deployment --region "$REGION" >/dev/null

aws ecs wait services-stable \
  --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION"
T_INJECT="$(now)"
log "service stable on regression revision (T_INJECT=$T_INJECT)"

# --- Traffic generator (background) ------------------------------------------
TRAFFIC_LOG="$TDDIR/traffic.log"
TRAFFIC_COUNTERS="$TDDIR/traffic.counters"
log "starting traffic generator: $TRAFFIC_RPS rps for ${DURATION_MIN}m"

(
  total=0; ok=0; err=0; net=0
  # Flush counters on any exit path (natural end, SIGTERM from parent's kill,
  # SIGINT from a parent ctrl-C). Without this, the parent's `kill` mid-loop
  # leaves $TRAFFIC_COUNTERS empty and the timeline JSON reports zeros.
  # Discovered in the 2026-04-29 GameDay run; CloudWatch metrics are the
  # authoritative source either way, but the script should not lie.
  flush_counters() {
    printf 'total=%d ok=%d err=%d net=%d\n' \
      "$total" "$ok" "$err" "$net" > "$TRAFFIC_COUNTERS"
  }
  trap flush_counters EXIT
  end=$(( $(date +%s) + DURATION_MIN * 60 ))
  interval=$(awk "BEGIN { printf \"%.3f\", 1.0 / $TRAFFIC_RPS }")
  while [[ $(date +%s) -lt $end ]]; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$ALB_DNS/" || echo 000)"
    total=$((total+1))
    case "$code" in
      2*) ok=$((ok+1)) ;;
      000) net=$((net+1)) ;;
      *) err=$((err+1)) ;;
    esac
    sleep "$interval"
  done
) > "$TRAFFIC_LOG" 2>&1 &
TRAFFIC_PID=$!

# --- Poll for fast-burn alarm to fire ----------------------------------------
log "polling $FAST_BURN_ALARM every ${POLL_INTERVAL}s; expected trip ~60min after inject"
T_ALARM_FIRES=""
DEADLINE=$(( $(date +%s) + DURATION_MIN * 60 + 600 ))  # +10 min slack
while [[ $(date +%s) -lt $DEADLINE ]]; do
  STATE="$(aws cloudwatch describe-alarms \
    --alarm-names "$FAST_BURN_ALARM" --region "$REGION" \
    --query 'MetricAlarms[0].StateValue' --output text)"
  if [[ "$STATE" == "ALARM" ]]; then
    T_ALARM_FIRES="$(now)"
    log "fast-burn alarm fired at $T_ALARM_FIRES"
    break
  fi
  log "fast-burn=$STATE; continuing to poll"
  sleep "$POLL_INTERVAL"
done

if [[ -z "$T_ALARM_FIRES" ]]; then
  log "WARN: fast-burn did not transition to ALARM within deadline"
fi

# --- Roll back ---------------------------------------------------------------
log "rolling back to $PRE_TD_ARN"
aws ecs update-service \
  --cluster "$CLUSTER" --service "$SERVICE" \
  --task-definition "$PRE_TD_ARN" \
  --force-new-deployment --region "$REGION" >/dev/null

aws ecs wait services-stable \
  --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION"
T_ROLLBACK="$(now)"
log "rollback complete; service stable on $PRE_TD_ARN (T_ROLLBACK=$T_ROLLBACK)"

# --- Stop traffic generator --------------------------------------------------
kill "$TRAFFIC_PID" 2>/dev/null || true
wait "$TRAFFIC_PID" 2>/dev/null || true
TRAFFIC_SUMMARY="$(cat "$TRAFFIC_COUNTERS" 2>/dev/null || echo 'total=0 ok=0 err=0 net=0')"

# --- Wait for all-clear (or skip and derive) ---------------------------------
T_ALL_CLEAR=""
if [[ "$SKIP_ALL_CLEAR_WAIT" == "true" ]]; then
  # The fast-burn alarm trails the metric by exactly its 1-hour window: even
  # after the metric drops below threshold, the rolling 1-hour aggregate
  # contains regression data and stays elevated until enough baseline data
  # rolls through. Skipping the wait saves ~60 min of AWS spend at the cost
  # of an observed T_ALL_CLEAR. The post-mortem documents the derived value.
  log "skipping all-clear wait (--skip-all-clear-wait); T_ALL_CLEAR is computed from rollback timestamp"
  # T_ROLLBACK + 60 min is the floor (one full alarm window of clean data).
  T_ALL_CLEAR_DERIVED="$(date -u -d "$T_ROLLBACK + 60 minutes" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
                       || python3 -c "import datetime as d; t=d.datetime.fromisoformat('${T_ROLLBACK%Z}'); print((t+d.timedelta(minutes=60)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
  T_ALL_CLEAR="$T_ALL_CLEAR_DERIVED"
else
  log "waiting for fast-burn to return to OK"
  ALL_CLEAR_DEADLINE=$(( $(date +%s) + 90 * 60 ))
  while [[ $(date +%s) -lt $ALL_CLEAR_DEADLINE ]]; do
    STATE="$(aws cloudwatch describe-alarms \
      --alarm-names "$FAST_BURN_ALARM" --region "$REGION" \
      --query 'MetricAlarms[0].StateValue' --output text)"
    if [[ "$STATE" == "OK" ]]; then
      T_ALL_CLEAR="$(now)"
      log "fast-burn returned to OK at $T_ALL_CLEAR"
      break
    fi
    log "fast-burn=$STATE; continuing to poll"
    sleep "$POLL_INTERVAL"
  done
fi

# --- Emit timeline -----------------------------------------------------------
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

jq -n \
  --arg t_pre        "$T_PRE" \
  --arg t_inject     "$T_INJECT" \
  --arg t_alarm      "${T_ALARM_FIRES:-null}" \
  --arg t_rollback   "$T_ROLLBACK" \
  --arg t_clear      "${T_ALL_CLEAR:-null}" \
  --arg pre_td       "$PRE_TD_ARN" \
  --arg reg_td       "$REGRESSION_TD_ARN" \
  --arg alb_dns      "$ALB_DNS" \
  --arg fast_pre     "$PRE_FAST_BURN_STATE" \
  --arg slow_pre     "$PRE_SLOW_BURN_STATE" \
  --arg traffic      "$TRAFFIC_SUMMARY" \
  --arg error_rate   "$ERROR_RATE" \
  --arg traffic_rps  "$TRAFFIC_RPS" \
  --arg duration_min "$DURATION_MIN" \
  --arg account      "$ACCOUNT_ID" \
  --arg region       "$REGION" \
  '{
    experiment: {
      account_id: $account,
      region: $region,
      cluster: "'"$CLUSTER"'",
      service: "'"$SERVICE"'",
      alb_dns: $alb_dns,
      injected_error_rate: ($error_rate | tonumber),
      configured_traffic_rps: ($traffic_rps | tonumber),
      configured_duration_min: ($duration_min | tonumber)
    },
    pre_state: {
      task_definition: $pre_td,
      fast_burn_alarm: $fast_pre,
      slow_burn_alarm: $slow_pre
    },
    timeline: {
      t_pre: $t_pre,
      t_inject: $t_inject,
      t_alarm_fires: (if $t_alarm == "null" then null else $t_alarm end),
      t_rollback: $t_rollback,
      t_all_clear: (if $t_clear == "null" then null else $t_clear end)
    },
    regression_revision: $reg_td,
    traffic: $traffic
  }' | tee "$TIMELINE_OUT"

log "timeline written to $TIMELINE_OUT"
log "next: fill in docs/post-mortem-2026-04-29-injected-regression.md from this JSON"
