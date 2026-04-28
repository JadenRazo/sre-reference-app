# Human Tasks

Manual gates queued for Jaden. The orchestrator updates this file as it works. Items move from `## Pending` to `## Done` once verified.

---

## Pending

### [Phase 0] Set up AWS account + IAM user
**Blocking:** Phase 3 onward. Phases 0.5, 1, 2 do not need AWS and run while you do this.

Steps:
1. Create AWS account (or use existing) at https://aws.amazon.com/
2. **Set up a billing alarm IMMEDIATELY** at the account level (Billing -> Budgets -> $10/month threshold). The orchestrator will also create a CloudWatch billing alarm via API once you have credentials, but the account-level budget is your second line of defense.
3. Create an IAM user named `sre-app-deploy` with **programmatic access**.
4. Attach the **AdministratorAccess** managed policy for the day. (We will narrow this in Phase 7 via the cicd module's deploy role; for the build day, admin is the path of least friction.)
5. Run on this machine:
   ```
   aws configure
   ```
   Enter access key id, secret access key, region `us-west-2`, output format `json`.
6. Verify with:
   ```
   aws sts get-caller-identity
   ```
   Should return your account ID and the `sre-app-deploy` user ARN.
7. Tell the orchestrator "AWS is configured" so it can proceed to Phase 3.

**Cost expectations for build day:** ~$5-20 if torn down by EOD. NAT gateway is the largest line item at ~$0.045/hr (~$1.08/day) plus data processing. ALB is ~$0.025/hr. ECS Fargate ~$0.04/hr per task at 0.25 vCPU / 0.5 GB. Plan ~$10/day if left running.

### [Phase 1] Confirm repo name
**Blocking:** GitHub repo creation step.

Default: `JadenRazo/sre-reference-app`, **public**. Already locked in plan; this gate exists only for last-minute change. If keeping default, no action needed.

---

## Done

(Tasks move here once verified. Each entry: `- [Phase N] <task> (<YYYY-MM-DD HH:MM PT>)`.)

---

## Resume notes

(If the orchestrator pauses mid-phase, exact next-action notes go here.)
