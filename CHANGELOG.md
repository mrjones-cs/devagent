# Changelog

All notable changes are listed here. Versions follow
[Semantic Versioning](https://semver.org/).

## 1.1.0 - 2026-10-20

Run `/plugin update` for both plugins, then `./install.sh` again (see "Updating"
in the README). Existing plans need the two new `01-requirements.md` sections
described below.

**Feature flags in the delivery workflow.** A feature can now be planned to
ship behind a flag, with the flag's removal planned from the start. DevAgent
ships no flag runtime and integrates with no flag vendor; the client's own
flag system stays in charge. See "Feature flags" in `docs/CUSTOMIZING.md`.

- **Grammar.** 02 and 05 take an optional `flagged: true` front-matter key
  (absent means `false`, so existing plans are unchanged). In a flagged 05 the
  add task carries `- flag: add <name>`, every task it guards carries
  `- flag on:` and `- flag off:` checks, and the remove task carries
  `- flag: remove <name>`, `- flag_owner: <role>` and `- remove_by:
  YYYY-MM-DD`. The `02-design.md` and `05-implementation.md` templates show
  them.
- **`check-plan.py` rule `flag-plan`.** Each flag has exactly one add and one
  remove task; the remove task has a client-side owner role and a real date;
  every other task is ordered against the add task, and the remove task comes
  after all feature work; every guarded task carries both checks. Flag keys
  are read from raw lines, so a repeated key or one hidden as an `owner`
  sub-field fails. A date in the past never fails the rule.
- **`check-plan.py --flags`** is a read-only report: one line per flag with
  its add state, owner, removal date and status (`live`, `overdue`,
  `removed` or `inconsistent`, plus `beyond a year` for a date more than a
  year out), `--all` across every plan, and `--today` for tests. A plan that
  fails its checks reports no flags and exits 1.
- **Build holds flag remove tasks.** `build-ready` leaves them out and prints
  `held for rollout: T-nn (flag <name>, remove by <date>)`.
  **`/delivery:build <feature> --remove-flags`** runs them once the rollout is
  finished. `save` reports the `--flags` lines in every mode; a 05 may be
  `complete`, and `save --handover` may deliver, with held remove tasks still
  open, and the handover manifest lists every flag not removed with its
  client-side owner, its date and the statement that the client owns removal.
- **Sanitised output.** Every line `check-plan.py` prints, and `build-ready`'s
  held line, is built from untrusted plan text, so Unicode control, format and
  line-separator characters (newline, ESC, U+202E) now print as `?` and a
  message is capped at 300 code points. Existing failure messages are
  otherwise unchanged.
- **New skill `devagent-standards:feature-flags`**, with its resident stub in
  `templates/CLAUDE.md`: default off, an owner and removal date for every
  flag, server-side evaluation for anything security-relevant, flagged-off
  code still ships, who may flip a flag, security controls never flag-gated,
  a kill switch for model calls, fail-safe defaults, gradual rollout, and
  hosted flag services treated as vendors. `engagement-closeout` lists live
  flags in the handover. If you keep your own copy of the resident rules, add
  the stub there too.
- **`scripts/check-all.sh`** runs `check-skills.py`, `check-plan.py` on the
  shipped example and every `scripts/test-*.sh` suite except the live smoke
  test, prints one line per suite with its exit code and time, and exits
  non-zero if any failed. It is the whole-repository gate before a push; each
  task's own verify stays the fast loop.

Fixes from a prompt audit of every file the model reads.

- **Requirements analyst** no longer tells itself to ask the operator questions
  it has no tool to ask. It takes every answer from the brief, writes `none
  stated` where there is none and lists those items so `brainstorm` can ask.
  It takes the tier the operator confirmed instead of a design section that
  does not ship with the plugin.
- **Delivery steps and agents** state the security-relevant change categories
  themselves instead of deferring to a bare "§3.4". `check-skills.py` now fails
  any section reference in a shipped plugin file that is not a parenthetical
  `(DESIGN §n)` beside a stated rule, with negative tests.
- **Requirements template** has `## Data handled` and `## Client constraints`
  sections. `brainstorm` always asked both; the template had nowhere to put
  the answers, so every draft placed them differently. `check-plan.py` now
  fails a 01 without either section, or with one left empty. **Existing
  plans:** add both headings to each `01-requirements.md`; `none stated` is a
  valid answer.
- **Resident rules template:** the nine `IMPORTANT:` section openers and the
  "NEVER EVER" are gone. The template already warns that a label on every
  section flattens the two HIGHEST PRIORITY banners; every rule and reason is
  unchanged. If you keep your own copy, make the same edit there.

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
