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

### [Phase 3/6] AWS FIS unavailable on this account - resolved by substitution
**Status:** resolved.

`aws_fis_experiment_template.stop_tasks` failed with `SubscriptionRequiredException` on first apply. Rather than blocking the build on a one-time AWS account opt-in (or paying for a support ticket), the project switched to `aws ecs stop-task` for the chaos trigger. Same blast radius, same recovery curve, $0 cost, no onboarding gate. The terraform module gates the FIS resources behind `var.enable_fis` (set to `false` in `terraform.tfvars`). Flip to `true` and re-apply if FIS becomes available later.

---

## Done

(Tasks move here once verified. Each entry: `- [Phase N] <task> (<YYYY-MM-DD HH:MM PT>)`.)

---

### [Phase 6/7] Three remaining screenshots
**Status:** pending. The README references all three by filename; once you drop the files in, the README starts rendering them.

| File | URL / source |
|---|---|
| `screenshots/06-chaos-task-stopping.png` | ECS console -> sre-app-cluster -> Tasks (Stopped tab) -> task `218ed9d99bee4b019b7dce71c36127a5`, OR the local terminal output of the `aws ecs stop-task` call |
| `screenshots/07-dashboard-during-chaos.png` | https://us-west-2.console.aws.amazon.com/cloudwatch/home?region=us-west-2#dashboards:name=sre-app-dashboard - set 1h time range, capture the recovery curve around 18:37-18:39 UTC. **Time-sensitive.** |
| `screenshots/08-github-actions-success.png` | https://github.com/JadenRazo/sre-reference-app/actions/runs/25071971120 - successful run with 13 green steps |

### [Phase 9] Cleanup decision
**Status:** pending. Reply `destroy` or `keep` and the orchestrator will run the cleanup or post a daily run-rate reminder.

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
