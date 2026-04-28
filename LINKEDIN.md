# LinkedIn drafts

This file lives in the repo because the build itself is part of the artifact. The build log entries below get synthesized into three polished post drafts in Phase 8.

## Style guide (enforced by the technical-writer subagent)

- **No em dashes.** Restructure with commas, periods, or parentheses.
- **ASCII only.** No smart quotes, no `…`. Use `'`, `"`, `...`.
- **Banned phrases:** `delve`, `leverage` (as a verb when "use" works), `robust`, `tapestry`, `intricate`, `comprehensive solution`, `in the realm of`, `at the end of the day`, `it's worth noting`, `in today's fast-paced`, `game-changer`, `unleash`, `cutting-edge`, `excited to share`, `thrilled to announce`, `seamless`, `empower`, `revolutionize`, `next-generation`, `world-class`.
- **Lead with a number or a concrete observation, not a generic intro.**
- **First two lines must hook before LinkedIn's "see more" cut.** Mobile cuts at ~210 chars; what comes before that is your only shot at click-through.
- No emojis. No `🚀`. No "I'm excited to share that...".

## Format budgets

| Format | Char budget | Phase target |
|---|---|---|
| Long-form story | 1200-1700 | Phase 6 (chaos, the headline post) |
| Single takeaway | 400-700 | Phase 7 (OIDC vs static keys) |
| Numbered list | 800-1200 | Phase 4-5 build-log synthesis |

## Build log

Phase-by-phase notes for later synthesis. Each entry is rough; the writer agent polishes them into final drafts in Phase 8.

### Phase 1 - Bootstrap - 2026-04-28
- Created public repo `JadenRazo/sre-reference-app`. Three project-scoped subagents in place to enforce style and infra hygiene before any code lands.
- The enforcement mechanism itself is a teachable moment: the reviewer agent greps for em dashes and banned phrases on every commit. If you can't grep for it, you can't enforce it.
- Surprise: writing the agent prompts forced me to articulate banned phrases I'd been letting slide for years in my own writing.

### Phase 2 - App + container - 2026-04-28
- Flask app + gunicorn behind a python:3.12-slim image. Two endpoints: `/health` always 200, `/` returns 500 with probability ERROR_RATE (default 0.05) so the SLO alarms have signal.
- Smoke test: 50 requests, 46x 200, 4x 500 (8% baseline, within expected variance for n=50).
- Surprise: my first JsonFormatter used `self.formatTime(record, "%Y-%m-%dT%H:%M:%S.%fZ")` and shipped literal `.%fZ` in every timestamp because Python's logging.Formatter uses `time.strftime` which doesn't expand `%f`. Switched to `datetime.fromtimestamp(record.created, tz=timezone.utc)`. Lesson: structured logs are only as good as the parser that reads them; CloudWatch Logs Insights would have failed silently on the malformed ISO timestamps.
- Second surprise: gunicorn's default access log was duplicating my Flask after_request JSON logs in plain text. Removed `--access-logfile -`, kept only the structured stream. One log format per service is a real rule, not a stylistic preference.

### Phase 3 - Terraform infra
(pending)

### Phase 4 - First deploy
(pending)

### Phase 5 - Observability + SLO
(pending)

### Phase 6 - Chaos with AWS FIS
(pending)

### Phase 7 - CI/CD via OIDC
(pending)

## Final drafts

(Synthesized in Phase 8.)

### Draft 1: Long-form chaos story
(pending)

### Draft 2: OIDC takeaway
(pending)

### Draft 3: Numbered build-log list
(pending)
