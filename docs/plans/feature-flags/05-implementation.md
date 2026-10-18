---
format: delivery-plan/1
feature: feature-flags
generator: delivery@1.0.1
step: 05-implementation
status: draft
date: 2026-10-17
reads: 01-requirements.md, 02-design.md, 03-research.md, 04-review.md
branch: feature-flags
base: 65c9d4e
verify_allowed:
  - bash scripts/test-check-plan.sh
  - bash scripts/test-check-plan.sh --coverage
  - env COVER=1 bash scripts/test-build-protocol.sh
  - python3 scripts/check-skills.py
  - bash scripts/check-all.sh
---

# Implementation plan: Feature flags

This plan builds the opt-in feature-flag convention in five parts:
- the `flag-plan` rule, central output sanitising and the `--flags` report
  in `check-plan.py`;
- the remove-task hold in `build-ready`;
- the `devagent-standards:feature-flags` skill with its resident stub and
  skill counts;
- the step-file and template changes;
- `scripts/check-all.sh` as the whole-repository gate.

Tier **M** (01). The plan is cut from the final `02-design.md`, with its
change log through C-15 and D-1 to D-4 decided by the operator. This plan
itself is unflagged: flags in DevAgent's own code are out of scope (01).

## How to read this
- Status: `[ ]` todo, `[~]` in progress, `[x]` done, `[!]` blocked.
- `verify` is the single command that proves a task and must appear in `verify_allowed`, with no shell operators.
- Evidence is written only by `run-verify`.
- T-01 → T-02 → T-03 share `plugins/delivery/scripts/check-plan.py` and `scripts/test-check-plan.sh`, so they run in sequence. T-04 and T-05 share no file with them and can run in parallel.
- `templates/CLAUDE.md` (T-05) is agent configuration, so build-integrate asks the operator to approve that path (`--approve-path`).

## Quality gates (apply to every task)

| Gate | Requirement | Source |
|---|---|---|
| G-1 | Every suite the task touches passes, and `python3 scripts/check-skills.py` stays clean | VERIFICATION |
| G-2 | Every new rule, condition and control has a negative test, and reintroducing the defect makes the suite fail. Each bad fixture names only its own rule | 02 §10, TESTING STANDARDS |
| G-3 | ≥ 80% line **and** branch coverage of the changed code in `check-plan.py` and `build-lib.py`, measured with `coverage==7.16.2` (pinned in `plugins/delivery/PINS.md`) | TESTING STANDARDS |
| G-4 | Standard library only; no new dependency; no new subprocess in `check-plan.py`; nothing read from a plan is executed | 01 NFR, 02 §7 |
| G-5 | The task's commit message states which OWASP categories were reviewed (A03 output injection, A04 gate design, A08 gate integrity) | OWASP SCREENING |
| G-6 | Every existing fixture and `examples/guard-report` pass unchanged | AC-2 |
| G-7 | `git diff` reviewed before the commit; one commit per task, message `T-nn: <title>` | VERIFICATION |

## Phase 1 — Checker

### T-01 [x] Central output sanitiser
- depends: none
- files: plugins/delivery/scripts/check-plan.py, scripts/test-check-plan.sh
- acceptance: one sanitiser in `check-plan.py` replaces Unicode `Cc`, `Cf`, `Zl` and `Zp` characters with `?`, and cuts any message over 300 code points to 299 plus `…`. `Failure.render` uses it for every line. A test-generated fixture whose invalid values hold ESC, U+202E and an embedded newline prints each failure on exactly one line, with `?` in place of each of those characters. A 400-character value prints at 300 code points. Every existing fixture's output is unchanged (02 §1.4, R-05)
- verify: `bash scripts/test-check-plan.sh`
- timeout: 10m
- evidence: run-verify · exit 0 · tests 92 · 9.8s · log evidence/T-01.log sha256:86ba249110a6e6de97208d410be7a7086d9a8992c515dec67a9390e85736776b · 2026-10-17

### T-02 [x] Rule `flag-plan` and its fixtures
- depends: T-01
- files: plugins/delivery/scripts/check-plan.py, scripts/test-check-plan.sh, tests/fixtures/plans/good-flagged/, tests/fixtures/plans/bad-flag-plan-*
- acceptance: `check-plan.py` implements 02 §1.2 conditions 1 to 6 under the single rule name `flag-plan`, reading flag keys from raw task lines. `good-flagged/` passes. It has two flags, a setup task before both add tasks, guarded tasks with `flag on` / `flag off`, and remove tasks still `[ ]`. Each `bad-flag-plan-*` fixture listed in 02 §10 fails and names only `flag-plan`. Every existing fixture and `examples/guard-report` still pass unchanged (AC-1, AC-2)
- verify: `bash scripts/test-check-plan.sh`
- timeout: 15m
- evidence: run-verify · exit 0 · tests 151 · 14.3s · log evidence/T-02.log sha256:a804fc18f169f9fb1ea09d3e9b04100df1f650af30f5919c3f2992d2cd460dc7 · 2026-10-17

### T-03 [x] `--flags` report mode and the coverage gate
- depends: T-02
- files: plugins/delivery/scripts/check-plan.py, scripts/test-check-plan.sh, tests/fixtures/plans/good-flagged/
- acceptance: `check-plan.py --flags <dir>` and `--flags --all [--today YYYY-MM-DD]` print exactly the 02 §1.3 lines. With a fixed `--today`, the tests cover:
  - `live`, `overdue`, `removed`, `inconsistent`, `beyond a year` and `no flags`;
  - `--all` across two folders, each line prefixed with its feature;
  - a failing folder, which prints `plan fails check-plan.py; flags not reported` and exits 1;
  - a bad `--today`, an unknown option and `--flags --hook`, each exiting 2;
  - an owner holding ESC and U+202E, printed with `?`.

  The `--coverage` run reports ≥ 80% line and branch coverage of `check-plan.py` (AC-4 report part, G-3)
- verify: `bash scripts/test-check-plan.sh --coverage`
- timeout: 15m
- evidence: run-verify · exit 0 · tests 181 · 21.2s · log evidence/T-03.log sha256:4981df86bb3ccb17f19d68345c4b90b558c9dd80fa5e3554dd47fccc5de8358c · 2026-10-17

## Phase 2 — Build hold and standard

### T-04 [x] `build-ready` holds flag remove tasks
- depends: none
- files: plugins/delivery/scripts/build-lib.py, plugins/delivery/scripts/build-ready, scripts/test-build-protocol.sh
- acceptance:
  - `build-ready` leaves out a ready task carrying `- flag: remove <name>` and prints `held for rollout: T-nn (flag <name>, remove by <date>)`.
  - `build-ready <dir> --removal` offers that task like any other.
  - The usage line shows `[--removal]`.
  - An unflagged plan's output is byte-for-byte unchanged.
  - A plan whose only ready task is held prints the held line and `no ready tasks`.
  - `COVER=1` reports ≥ 80% line and branch coverage of the changed lines (02 §1.5, R-04)
- verify: `env COVER=1 bash scripts/test-build-protocol.sh`
- timeout: 15m
- evidence: run-verify · exit 0 · tests 120 · 25.3s · log evidence/T-04.log sha256:feb4d7281fcbe3b85b1df7d1cb9ee7b4fae99fbd9990f9e487ed5a5d7e274f9c · 2026-10-17

### T-05 [ ] `feature-flags` skill, resident stub and skill counts
- depends: none
- files: plugins/devagent-standards/skills/feature-flags/SKILL.md, plugins/devagent-standards/skills/engagement-closeout/SKILL.md, templates/CLAUDE.md, README.md, docs/DESIGN.md, .claude-plugin/marketplace.json, plugins/devagent-standards/.claude-plugin/plugin.json
- acceptance:
  - `skills/feature-flags/SKILL.md` has front matter `name` and `description`, the description naming when to invoke it. It covers every 02 §1.7 section, each as a rule with its reason: server-side and session-scoped evaluation, client-side exposure, flagged-off code in public bundles, who may flip a flag with MFA and audit, security controls never flag-gated, a model kill switch that fails off, fail-safe defaults, gradual rollout, and hosted services as vendors.
  - `templates/CLAUDE.md` gains a stub under DETAILED STANDARDS in the existing format.
  - `engagement-closeout` gains the live-flags handover line.
  - The skill count reads 14 / fourteen in every file 02 §10 lists, and the manifest skill lists name feature flags.
  - The resident line, word and token figures are updated wherever `check-skills.py` reads them.
  - `check-skills.py` is clean, and `bash scripts/test-check-skills.sh` still passes (AC-5).
- verify: `python3 scripts/check-skills.py`
- timeout: 20m

## Phase 3 — Workflow text

### T-06 [ ] Step files, build wrapper and templates
- depends: T-03, T-04, T-05
- files: plugins/delivery/references/steps/design.md, plugins/delivery/references/steps/workflow.md, plugins/delivery/references/steps/build.md, plugins/delivery/references/steps/save.md, plugins/delivery/skills/build/SKILL.md, plugins/delivery/references/templates/02-design.md, plugins/delivery/references/templates/05-implementation.md, tests/fixtures/plans/from-templates/02-design.md, tests/fixtures/plans/from-templates/05-implementation.md
- acceptance: the steps and templates say what 02 §1.6 says.
  - `design.md` sets `flagged` and invokes the skill.
  - `workflow.md` writes the add task first and the remove task last, `flag on` / `flag off` bullets, a client-side `flag_owner` role, and a both-states quality gate.
  - `build.md` documents the hold and `--remove-flags`, and the build wrapper's `argument-hint` adds `--remove-flags`.
  - `save.md` runs `--flags` in every mode, handles exit 1 as 02 §1.3 says, allows `complete` with only held remove tasks open, and lists open flags in the handover manifest with a client-side owner and the client-owns-removal statement.
  - The templates gain `flagged` and the flag-bullet comment, and the `from-templates` fixture is updated to match and passes `check-plan.py`.
  - `check-skills.py` is clean, with no bare section reference.
  - Named AC-3 step: `workflow` is run on a copy of `good-flagged/02-design.md` in a scratch folder. The 05 it writes passes `check-plan.py` with the add task first, the remove task last, and both bullets on every guarded task. The outcome is recorded in the commit message (AC-3, AC-4 save part)
- verify: `python3 scripts/check-skills.py`
- timeout: 20m

## Phase 4 — Records and gate

### T-07 [ ] DESIGN grammar and CHANGELOG
- depends: T-06
- files: docs/DESIGN.md, CHANGELOG.md
- acceptance:
  - DESIGN §5.1 lists the optional `flagged` key for 02 and 05.
  - §5.5 shows the flag bullets.
  - §5.6 lists `flag-plan`, `--flags` and output sanitising.
  - §4.4 describes the build hold.
  - CHANGELOG's Unreleased section describes the feature, `--remove-flags`, `check-all.sh` and the sanitised output.
  - `check-skills.py` is clean
- verify: `python3 scripts/check-skills.py`
- timeout: 10m

### T-08 [ ] `scripts/check-all.sh` and the whole-repository gate
- depends: T-01, T-02, T-03, T-04, T-05, T-06, T-07
- files: scripts/check-all.sh, README.md
- acceptance:
  - `scripts/check-all.sh` runs, in sequence: `python3 scripts/check-skills.py`, `python3 plugins/delivery/scripts/check-plan.py examples/guard-report`, and every `scripts/test-*.sh` except `test-delivery-smoke.sh`.
  - It prints one line per suite with its exit code and seconds, then a total.
  - It exits non-zero if any suite fails, and exits 2 on any argument.
  - README's check-command list gains it, with its measured run time.
  - The run passes with every suite green (AC-6). CI confirms it again on the first push of the integrated branch, which build does not do
- verify: `bash scripts/check-all.sh`
- timeout: 15m
