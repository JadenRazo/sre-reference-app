# Screenshots index

Place screenshots in this directory using the exact filenames below. The README and LinkedIn drafts reference them by name; missing files break the reviewer pass.

| File | Phase | What to capture |
|---|---|---|
| `02-ecr-repository.png` | 4 | ECR console showing the `sre-reference-app` repo with at least one image tag pushed. |
| `03-ecs-service-running.png` | 4 | ECS console -> cluster -> service, showing 2/2 tasks running and the ALB target group healthy. |
| `04-cloudwatch-dashboard.png` | 5 | The custom CloudWatch dashboard during sustained traffic. Visible: request count, p50/p99 latency, 5xx rate, ECS task count, target health. |
| `05-burn-rate-alarm.png` | 5 | CloudWatch Alarms list, both fast-burn and slow-burn alarms in `OK` state. |
| `06-chaos-task-stopping.png` | 6 | Terminal output of the `aws ecs stop-task` chaos invocation, OR the ECS console showing the stopped task with stoppedReason. (FIS not available on this AWS account; substituted with stop-task.) |
| `07-dashboard-during-chaos.png` | 6 | CloudWatch dashboard 1h or 3h view showing the task count drop and recover, 5xx blip, and recovery curve from the chaos run. |
| `08-github-actions-success.png` | 7 | Successful GitHub Actions workflow run for `deploy.yml`, showing the OIDC auth step and `aws ecs wait` completing green. |

Take screenshots at native resolution. PNG only (no JPG). Crop to the relevant panel; full-screen browser shots are too noisy to read in a README embed.
