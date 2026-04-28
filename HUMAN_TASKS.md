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

### [Phase 3/6] Enable AWS FIS in this account (one-time)
**Blocking:** Phase 6 chaos experiment (does NOT block Phase 4 deploy or Phase 5 observability).

The first `terraform apply` failed on `aws_fis_experiment_template.stop_tasks` with `SubscriptionRequiredException: The AWS Access Key Id needs a subscription for the service`. AWS FIS requires a one-time account opt-in that happens automatically when you visit the FIS console.

Steps:
1. Open https://us-west-2.console.aws.amazon.com/fis/home?region=us-west-2
2. Read the welcome page and click any "Get started" / "Continue" button. The act of loading the console accepts the FIS service terms for this account.
3. Tell the orchestrator "FIS is enabled" and it will run:
   ```
   cd /root/sre-reference-app/infra && terraform apply -target=module.observability.aws_fis_experiment_template.stop_tasks
   ```
   That single-resource apply finishes in ~5 seconds and the project is back on track for Phase 6.

---

## Done

(Tasks move here once verified. Each entry: `- [Phase N] <task> (<YYYY-MM-DD HH:MM PT>)`.)

---

## Resume notes

**Pause point:** End of Phase 2 (2026-04-28). All AWS-independent work is shipped. Resuming requires AWS credentials.

**Next action when AWS is configured:**
1. Run `aws sts get-caller-identity` to confirm. Tell the orchestrator "AWS is configured."
2. The orchestrator will then:
   - Create the $10 CloudWatch billing alarm (us-east-1, since billing metrics live there).
   - Begin Phase 3: write `infra/{main,variables,outputs,providers}.tf` (top-level wiring), then dispatch 4 `terraform-architect` agents in parallel for `modules/{network,service,observability,cicd}`, plus 1 `technical-writer` for `docs/slos.md`.
   - Run `terraform init && validate && plan -var "region=us-west-2" -out=tfplan`.
   - Show you the plan summary and wait for `continue` before Phase 4 apply.

**Cost note (read once):** From the moment `terraform apply` runs, AWS bills NAT gateway (~$0.045/hr), ALB (~$0.025/hr), and Fargate tasks (~$0.04/hr at 0.25 vCPU). About $0.11/hr or ~$2.60/day idle. Ten dollars covers ~3.8 days. Plan to destroy by end of build day unless interview demos are scheduled.
