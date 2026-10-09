# Working on SRE Reference App

Demonstrate service reliability and incident recovery with measured, reproducible
evidence. The Flask/ECS lab was torn down after the recorded exercises; its code,
screenshots and post-mortems remain. A maintenance task must not recreate it.

## Route by change

- App behavior: `app/main.py`, `app/tests/test_main.py`, `pyproject.toml` and
  `app/requirements-dev.txt`. Preserve `/health`, deliberate configurable error
  injection, request IDs and structured request logs. Read executable routes
  rather than inferring endpoints from older README layout text.
- Infrastructure: `infra/main.tf`, the affected network/service/observability/
  cicd module, `.github/workflows/terraform.yml`, and `docs/security-baseline.md`.
  Keep accepted lab exceptions explicit; do not broaden scanner exclusions to
  make a change pass or portray this baseline as production hardening.
- SLOs and drills: `docs/slos.md`, actual alarm definitions,
  `docs/chaos-experiments.md`, the dated regression post-mortem and
  `regression-timeline.json`. `runbooks/high-latency.md` is an operational
  procedure, not an instruction to inject a fault during routine maintenance.
- Deployment: `.github/workflows/deploy.yml` is the current trigger authority.
  Older README text mentions push deployment; the current workflow is manual
  with `deploy-lab` confirmation and the `sre-reference-app-lab` environment.

## Preserve evidence and operating limits

Keep PR/main test and Terraform checks credential-free; preserve manual cloud
deployment, immutable Actions and source-SHA image tags. Environment declarations
do not prove configured reviewer protections. Before an authorized live session,
confirm account, region, state owner, resources, cost/cleanup scope and recovery.
Never run apply/destroy, image pushes, task termination, FIS or
`scripts/inject-regression.sh` as a local test. Keep FIS disabled unless its
separate live exercise is authorized. Protect state, plans and raw sensitive logs.

Retain exact conditions beside measured results: one task terminated in a
two-task service, sampled traffic, time window, injected error rate and alarm
state. The recorded 78-second recovery is not a general RTO or a 30-day SLO
guarantee. An alarm in OK with missing data does not prove healthy traffic.
Preserve the post-mortem's failed hypothesis and corrected observation; separate
derived all-clear times from observed transitions and incomplete timeline fields
from measured totals. Do not overwrite a historical receipt with a new run.
Historical costs are neither current prices nor standing spending approval.

## Validation and delivery

With existing dependencies available, run `python -m pytest` from the root for
application changes. For Terraform changes, CI runs these from `infra/`:

```sh
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
tflint --recursive --format=compact
```

Initialization and TFLint plugin setup may download dependencies; use the workflow
for versions/setup and its Checkov exception list. These are static checks, not
cloud acceptance. For documentation changes, verify links and claims against
the named sources; no fault drill or container build is required. Visual changes
follow `diagrams/README.md` and their generator rather than hand-editing PNGs.

Write docs and PRs around the problem, resulting behavior, meaningful validation
and material limits. Use plain words and link evidence instead of replaying logs.
Follow repository commit conventions, otherwise use `type: concrete change`
(preferably under 72 characters). State which checks ran and actual push/PR or
deployment effects; a successful local test is not a recovered cloud service.
