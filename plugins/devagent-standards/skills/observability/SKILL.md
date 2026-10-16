---
name: observability
description: Standard for making a system operable. Use when designing or handing over a customer-facing system - structured logging, correlation IDs, health/liveness/readiness endpoints, metrics, tracing, alerting and thresholds, availability/latency/durability targets, backups and restore testing (RTO/RPO), data residency, runbooks, and naming the patching owner. Also use when a system needs to answer "whose data, which records, what window" for a breach clock.
---

# Observability and Operational Readiness

A system the customer cannot operate is not delivered. Under a fixed bid,
"it works but nobody can tell when it stops" is unbilled support we
absorb — so operability is scope, defined before the build, not a
courtesy added at handover.

## Logging

- **Structured, machine-parseable logs** (JSON), not free-text prose.
  One event per line, consistent field names.
- **A correlation ID on every request**, propagated across service
  boundaries and present in every log line and error response, so a
  customer's report maps to a trace.
- **Levels used honestly**: ERROR is actionable, WARN is degraded, INFO
  is business events, DEBUG is off in production.
- **Never log secrets, tokens, credentials, or PII** — see the
  `encryption` and `llm-app-security` skills. Log identifiers, not
  payloads.

## Health, metrics and tracing

- **Separate liveness from readiness.** Liveness answers "is the process
  up"; readiness answers "can it serve." A load balancer needs both and
  they fail differently. Neither leaks version, config, or counts — see
  deny-by-default in the `auth-portal` skill.
- **The four golden signals as the baseline**: latency, traffic, errors,
  saturation. Add queue depth and dependency health where they apply.
- **Distributed tracing once more than two services sit in a request
  path.** Below that, correlation IDs in logs are enough — do not build
  a tracing stack for a monolith.
- **Cost is a telemetry signal too** — see Cost Discipline in the
  `cloud-infra` skill. Budget alarms belong to the observability
  baseline, not just the finance one.

## Alerting

- **Alert on symptoms, not causes.** "Checkout error rate above 2%" is
  actionable; "CPU at 80%" is usually noise.
- **Every alert carries a runbook link and a named owner.** An alert
  nobody knows how to action trains people to ignore alerts.
- **No alert without a threshold you can defend.** State the number and
  why it is that number.

## State the targets with the design

- **Define availability, latency, and durability targets before
  building**, alongside the cost estimate. They drive architecture and
  cannot be retrofitted from it.
- **Backups exist, are encrypted, and are restore-tested.** State RTO
  and RPO explicitly. The `encryption` skill requires backups be
  encrypted and says nothing about whether they exist or whether a
  restore was ever attempted — an untested backup is a hope, not a
  control.
- **Data residency**: state which regions the system runs and stores in.
  US-only unless the contract says otherwise; federal work may require a
  specific boundary, and that is a design input, not a deployment detail.

## The handover artifact

Every customer-facing system ships with a runbook covering: how to
deploy, how to roll back, how to read the logs, what each alert means,
where the secrets live, who to call at each vendor, and how to tear it
down. Teardown is already a deliverable under the `cloud-infra` skill —
the runbook is that same obligation for the parts that stay.

**Name the patching owner and the cadence before handover.** A system
starts decaying the day it ships: dependencies, base images, runtimes and
TLS certificates all expire on somebody's watch. Put in writing whose. If
it is the customer, the runbook says how they do it; if it is us, it is a
support arrangement with a price attached, not a favour we absorb. Under
a fixed bid an unowned patching obligation is unbilled work we get called
about anyway.

## Design for the breach clock

A system that cannot answer "whose data, which records, over what window"
within a day cannot meet a 72-hour notification obligation. That is a
logging and data-model requirement during the build, not an
incident-time scramble. See the `incident-breach` skill for the clock
itself.

## Verify, do not assume

- **Prove the telemetry exists on the deployed surface** before
  reporting done: trigger a real error and find it in the logs by
  correlation ID; confirm both health endpoints answer correctly.
- **Fire one alert deliberately** and confirm it reaches a human.
- Report what was exercised, as with every other verification.

## Related

- OWASP Top 10 checklist: `${CLAUDE_PLUGIN_ROOT}/references/owasp-top10.md` (category 9)
- `incident-breach` — the notification clock this logging serves
- `cloud-infra` — budget alarms, teardown scripts
- `api-security` — per-client volume alarms
- `engagement-closeout` — everything else about leaving: access
  revocation, transfers, licence attestation, who owns the gap
