---
format: delivery-plan/1
feature: guard-report
generator: delivery@v1.4.0
step: 01-requirements
status: draft
date: 2026-10-16
tier: M
ai_use: none (no model calls)
---

# Requirements: Guard report

## Goal
Give the operator a command-line summary of the devagent-guard audit log, so
they can decide on evidence whether to flip the guard from warn to enforce:
which rules fire, how often, where, and what enforce mode would have done.

## Users and context
- Users: the operator only.
- Context: an internal tool in `devagent`, delivered as
  `scripts/guard-report.py` in this repository. Never a client deliverable.
- Input: the guard audit log under `~/.claude/devagent-audit/<engagement>/YYYY-MM.jsonl`,
  one partition folder per engagement.
- Existing codebase binds the stack (operator-stated): Python 3.11+, standard
  library only.
- Data handled: tool-call metadata already redacted by the guard (commands,
  file paths, rule names). Paths and engagement folder names can reveal which
  client engagements exist, so the log and the report are
  Confidential. Personal data: none beyond the operator username in
  paths. Regulated data: none stated. Credentials: none - the log is
  redacted. Client IP: none beyond what engagement names imply. Production
  data: none.
- Client constraints: none - internal tool (no SSO/IdP, cloud, region,
  vendor list, compliance regime or contract clause applies).
- AI-use position: the tool does not call a model, retrieve documents for a
  model, or give an agent tools.

## Functional requirements
1. Read every `YYYY-MM.jsonl` file under the audit directory, across all
   engagement partitions.
2. Report the total number of tool calls recorded.
3. Report guard matches per rule, each with the action enforce mode would
   take for that rule (deny or ask).
4. Report matches per engagement.
5. Report matches per day.
6. For each rule, list up to 10 distinct matched commands or paths, each
   truncated to 120 characters.
7. List the rules that never fired.
8. Count malformed lines and report the count; a malformed line never stops
   the run.
9. `--since YYYY-MM-DD` limits the report to records on or after that date.
10. `--engagement NAME` limits the report to one engagement partition.
11. `--audit-dir PATH` selects the audit directory; default
    `~/.claude/devagent-audit`.
12. Write the report to stdout only.
13. Exit 0 on success, 2 on a usage error, 3 when the audit directory is
    missing or unreadable.

## Non-functional requirements
- Read-only: never writes, renames or touches anything under the audit
  directory.
- Confidentiality: output goes to stdout only - never written to a file,
  never sent anywhere; no network access.
- Never attempts to reverse or un-redact any redacted value in the log.
- Performance: under 2 s for 10,000 records.
- Runtime: Python 3.11+, standard library only (no new dependency, so no
  licence question arises).
- Every item in the output is at most 120 characters.
- Tests: line and branch coverage >= 80%.

## Acceptance criteria
- AC-1: On a fixture audit directory, every reported count (total calls,
  per rule, per engagement, per day, never-fired rules) matches the fixture
  exactly.
- AC-2: A fixture containing a malformed line produces a report in which
  that line is counted and reported, and the run exits 0.
- AC-3: `--since` and `--engagement` each filter the fixture to exactly the
  expected records.
- AC-4: No item in the output exceeds 120 characters, including for a
  fixture command longer than 120 characters.
- AC-5: File mtimes and contents in the audit directory are unchanged after
  a run.
- AC-6: A bad option exits 2; a missing or unreadable audit directory exits 3.
- AC-7: A 10,000-record fixture is reported in under 2 s.
- AC-8: Line and branch coverage of the script's tests is >= 80%.

## Out of scope
- Changing `guard.py` or its rules.
- Flipping the guard's MODE.
- Any network access.
- Any UI.
- Any model call.
- Writing the report to a file.

## Tier
M, operator override. On its own this is S: one script and its test, no new
data store, public endpoint, login or external service, and fewer than five
tasks - no M trigger fires. The operator overrides to M because the
pilot must exercise `/delivery:plan` chaining design, research, spec-panel
and workflow.

## Notes for design
- Standards that apply at design: `stack-selection` is settled by the
  existing codebase (Python 3.11+ stdlib). `llm-app-security` does not
  apply (no model). `auth-portal`, `api-security`, `web-browser-security`,
  `encryption` and `cloud-infra` do not apply: no login, endpoint, browser
  surface, new data store or cloud resource.
- Open question for design: where the per-rule enforce action (deny or ask)
  is sourced from, given `guard.py` must not change.

## Revisions
- 2026-10-16: initial draft from the headless pilot brainstorm.
