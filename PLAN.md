# PLAN.md - Agent Orchestration for SRE Reference App

> Companion plan that drives the orchestrated build of this repo. Read this before starting Phase 0.

---

## 1. Operating model

The main Claude Code instance is the **orchestrator**. It does not write code directly when a subagent can do it better or in parallel. It plans, dispatches, integrates, and gates commits.

Three rules that govern every phase:
1. **If two tasks have no shared file dependency, dispatch them in parallel.** Single-message multi-tool-call.
2. **Every phase ends with a reviewer pass before the commit.** No exceptions.
3. **Manual work is queued, not interleaved.** Batch human checkpoints at phase boundaries.

---

## 2. Agent team

### Custom subagents (defined in Phase 0.5, live under `.claude/agents/`)

#### 2.1 `terraform-architect`
**Role:** All `.tf` file authorship and modifications.
**Tools:** Read, Write, Edit, Bash (for `terraform fmt`, `validate`, `plan`)
**System prompt enforces:**
- Modular structure: `modules/{network,service,observability,cicd}` only
- Always `terraform fmt` and `validate` before declaring done
- Never put inline IAM policy JSON in resources; use `aws_iam_policy_document` data sources
- Never hardcode account IDs, region strings, or ARNs; pull from data sources or variables
- Tag every taggable resource via provider `default_tags`
- Output values for anything another module needs
- Use `~> 5.0` for AWS provider; never pin to exact patch
- For ECS task defs, always set `propagate_tags = "TASK_DEFINITION"` and tag tasks `FIS-Target = "true"`

#### 2.2 `technical-writer`
**Role:** All human-facing markdown: README, runbooks, post-mortem template, architecture doc, LinkedIn drafts.
**Tools:** Read, Write, Edit
**System prompt enforces:**
- No em dashes; use commas, periods, or restructure
- No smart quotes; ASCII only
- Banned phrases: "delve," "leverage" (as verb when "use" works), "robust," "tapestry," "intricate," "comprehensive solution," "in the realm of," "at the end of the day," "it's worth noting," "in today's fast-paced," "game-changer," "unleash," "cutting-edge," "excited to share," "thrilled to announce"
- Lead with concrete observations or specific numbers, never generic intros
- Every doc with a technical claim cites a specific number (latency ms, percentage, time elapsed, dollar cost)
- Direct second-person voice in runbooks, third-person in post-mortems
- LinkedIn drafts: 1200-1700 chars long-form, 400-700 chars single-takeaway, 800-1200 chars numbered list. First two lines must hook before LinkedIn's "see more" cut.

#### 2.3 `reviewer`
**Role:** Final gate before every commit. Reads all changed files, runs validation commands, fails loudly.
**Tools:** Read, Bash, Grep
**System prompt enforces:** see `.claude/agents/reviewer.md` for the full checklist (em dash grep, banned-phrase grep, secrets grep, `terraform fmt -check`, `terraform validate`, `python -m py_compile`, Dockerfile HEALTHCHECK presence, workflow YAML parse, README screenshot reference integrity).

### General-purpose subagent
For everything else: Flask app, Dockerfile, GitHub Actions YAML, Docker local testing, `aws` CLI calls, `gh` CLI calls, git operations, file scaffolding.

---

## 3. Phase plan

### Phase 0 - Pre-flight (orchestrator only)
- Tool inventory: `git`, `gh`, `docker`, `terraform`, `aws`, `python3`, `jq`
- Verify auth: `aws sts get-caller-identity`, `gh auth status`
- Capture region: `aws configure get region`
- Print summary, queue any missing-tool checkpoints

### Phase 0.5 - Define agent team
Write the three custom subagent files to `.claude/agents/`. Verify each loads.

### Phase 1 - Bootstrap project + GitHub
Parallel: directory tree + `.gitignore` + scaffolding docs, alongside README skeleton + `LINKEDIN.md` scaffold. `git init -b main`, initial commit, `gh repo create ... --push`. Tag `phase-1-complete`. Reviewer pass.

### Phase 2 - App + container
Parallel: `app/main.py` with structured JSON logging + `app/requirements.txt`, alongside `app/Dockerfile` with HEALTHCHECK. Local docker build + smoke test (200 on `/health`, occasional 500s on `/`). Reviewer pass. Commit, tag `phase-2-complete`.

### Phase 3 - Terraform infra
Sequential first: `infra/{main,variables,outputs,providers}.tf` (top-level wiring, lock module interface contracts).
Parallel: 4x `terraform-architect` against `modules/{network,service,observability,cicd}`, plus `technical-writer` drafting `docs/slos.md`.
Integrate: `terraform init && validate && plan -var "region=us-west-2" -out=tfplan`. Reviewer pass (no inline IAM JSON, no hardcoded ARNs, all modules expose required outputs, fmt+validate clean). Manual gate: review plan, type `continue`. Commit, tag `phase-3-complete`.

### Phase 4 - First deploy
Sequential: `terraform apply tfplan`, ECR login + build + tag + push, ECS force-new-deployment, `aws ecs wait services-stable`, smoke test 20 curls.
Parallel: writer Phase 4 build-log entry. Manual gate: screenshots `02-ecr`, `03-ecs`. Reviewer light pass. Commit, tag `phase-4-complete`.

### Phase 5 - Observability + SLO verification
Sustained traffic 5 min. Print dashboard URL. Query alarm states (both `OK`).
Parallel: writer finalizes `docs/slos.md` with verified numbers + Phase 5 LinkedIn entry. Manual gate: screenshots `04-dashboard`, `05-burn-rate`. Reviewer light. Commit, tag `phase-5-complete`.

### Phase 6 - Chaos with AWS FIS
Background load generator, wait 60s. **Manual gate (the big one):** run FIS experiment from console, screenshots `06`, `07`, type `continue`.
After: stop load gen, query alarms (still `OK`). Dispatch writer for `docs/chaos-experiments.md` (hypothesis/method/result/findings) and the headline LinkedIn entry. Reviewer mandatory. Commit, tag `phase-6-complete`. **Most important commit of the project.**

### Phase 7 - CI/CD
Sequential: terraform apply confirmed (cicd module already in plan from Phase 3). Capture deploy role ARN.
Parallel: workflow YAML + writer Phase 7 LinkedIn entry. Manual gate: `gh secret set` commands run by Jaden. Trigger workflow with trivial commit, `gh run watch`. Manual gate: screenshot `08`. Reviewer (workflow YAML parse, OIDC trust policy repo-scoped). Commit, tag `phase-7-complete`.

### Phase 8 - Final docs + LinkedIn
Parallel A-D: runbook, post-mortem template, architecture doc with Mermaid, final README. Then writer E synthesizes build-log into 3 final post drafts in `LINKEDIN.md`.
Heavy reviewer pass (full banned-phrase grep across every `.md`, not just changed). Manual gate: pick a draft, post manually. Commit, tag `phase-8-complete`.

### Phase 9 - Cleanup decision
Manual gate: `destroy` or `keep`. If destroy: `terraform destroy -auto-approve`, writer adds "Status: torn down" footer to README, final commit.

---

## 4. Manual work (consolidated)

| Phase | Action | Approx time |
|-------|--------|--------------|
| 0 | Confirm AWS account, billing alarm, IAM user, `aws configure`, `gh auth login` | 15 min one-time |
| 1 | Confirm GitHub repo name | 30 sec |
| 3 | Review `terraform plan`, authorize apply | 2 min |
| 4 | Screenshots: ECR repo, ECS service running | 2 min |
| 5 | Screenshots: dashboard, burn-rate alarm | 2 min |
| 6 | Run FIS experiment from console, screenshots: experiment running, dashboard during chaos | 5 min |
| 7 | Add GitHub repo secrets, screenshot of successful workflow run | 3 min |
| 8 | Read LinkedIn drafts, post one to LinkedIn | 5 min |
| 9 | Choose destroy or keep | 30 sec |

Total manual time: ~35 minutes spread across the build day.

---

## 5. Failure modes and recovery

**terraform apply fails:** orchestrator reads error, dispatches `terraform-architect` to fix, re-runs `validate` and `plan`, asks for re-authorization before re-applying.

**ECS service fails to stabilize:** orchestrator pulls task logs via `aws logs tail`, identifies error, dispatches general-purpose to fix app or `terraform-architect` to fix infra. No blind retries.

**reviewer rejects:** orchestrator dispatches fix to the originating agent with the reviewer's blocker list, re-runs reviewer.

**Subagent returns inadequate work:** orchestrator does not silently accept. Re-dispatches with sharper framing or splits the task smaller.

**User goes idle mid-phase:** orchestrator updates `HUMAN_TASKS.md` with a "Resume notes" section pointing to exact next action, then exits cleanly. No partial commits left dangling.

---

## 6. Definition of done

- [ ] Repo public on GitHub with all 8 phase tags pushed
- [ ] All 8 expected screenshots present in `screenshots/`
- [ ] `README.md` includes architecture diagram, SLO summary, screenshot embeds, quickstart, "what this demonstrates" list
- [ ] `infra/` passes `terraform fmt -check` and `terraform validate`
- [ ] `LINKEDIN.md` contains three polished post drafts that pass the banned-phrase grep
- [ ] Reviewer agent's final pass returns green
- [ ] `PROGRESS.md` shows all phases done with completion timestamps
- [ ] `HUMAN_TASKS.md` is empty under "Pending"
