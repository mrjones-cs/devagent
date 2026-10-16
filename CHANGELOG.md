# Changelog

All notable changes are listed here. Versions follow
[Semantic Versioning](https://semver.org/).

## 1.0.1 - 2026-10-16

Fixes found by installing from the public GitHub URL and running a real feature
through the workflow end to end. Run `/plugin update` for both plugins, then
`./install.sh` again (see "Updating" in the README).

- **Installer:** a plugin update no longer leaves the old research permission
  rule behind. The plugin cache path carries the version, which the cleanup did
  not recognise.
- **`/delivery:load`** no longer shows a failing plan check in a project that
  has no plans yet.
- **Plan checker:** a task that changes none of its files, for example "prove
  the suite passes on another interpreter", is no longer reported as having no
  commit; its commit counts through its evidence log. A second commit for the
  same task is still caught.
- **Design template:** open decisions are written as a table, the only form the
  checker reads as a definition. A review finding sent to the operator against a
  template-written design used to fail with a dangling reference.
- **Guard:** the "no PostToolUse heartbeat" warning no longer fires in a session
  that ran no tools, which is what every new user's first session looks like.
- **Smoke test** follows the plugin to wherever Claude Code loaded it from, so it
  passes for the GitHub-URL install the README recommends. It records into a
  gitignored `.smoke/` folder.
- **CI** now fails any push that names a term the maintainers keep out of the
  repository (files, names and history, binary files included). Writing its
  tests exposed that git's history search skips binary files unless asked not to.

## 1.0.0 - 2026-10-16

First public release (never tagged; superseded by 1.0.1).

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
