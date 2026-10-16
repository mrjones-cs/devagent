# Changelog

All notable changes are listed here. Versions follow
[Semantic Versioning](https://semver.org/).

## 1.0.0 - unreleased

First public release.

- **Resident rules template** (`templates/CLAUDE.md`) with an ORGANISATION
  block the skills read from, and an installer that links your own rules
  file (`./install.sh --rules FILE`) or starts you from the template.
- **`devagent-standards`**: 13 on-demand skills, the OWASP checklist, and
  **`devagent-guard`**: 10 rules that deny or ask in enforce mode (the
  default), quote-aware command parsing, a per-project audit log, and a
  session health check (including a warning for projects whose `AGENTS.md`
  would load as instructions).
- **`delivery`**: nine user-invoked workflow steps, four agents, eleven
  review lenses, the `delivery-plan/1` grammar and its checker, evidence
  written only by `run-verify`, a scope-checked build protocol that never
  pushes, a structure-only session briefing.
- **Optional web search** through AWS Bedrock AgentCore, with a Terraform
  module; without it, research confirms facts on official pages.
- `scripts/guard-report.py`: a read-only report of the audit log.
- `examples/guard-report/`: a complete delivery record.
