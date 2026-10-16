---
format: delivery-plan/1
feature: guard-report
generator: delivery@v1.4.0
step: 04-review
status: draft
date: 2026-10-16
reads: 01-requirements.md, 02-design.md, 03-research.md
classification: Confidential
---

# Review: Guard report

## Summary

Tier M panel: builder, attacker, pre-mortem, each a fresh `delivery:reviewer`
on Sonnet, dispatched in parallel and blind to one another. Deviation from
spec-panel.md, recorded for the pilot: 02 was handed to each reviewer by path
with an instruction to read it whole, not inlined in the prompt; lens text,
01's acceptance criteria and 03's 🔄/⛔ rows (none) were inlined.

15 raw findings (6 high, 7 medium, 2 low) merged to 11: 6 high, 4 medium,
1 low. Outcomes: 11 applied (R-01..R-11), 0 needs-decision, 0 rejected, 0
accepted risk. Rejection rate per lens: builder 0/5, attacker 0/5,
pre-mortem 0/5.

Nine findings were routed to the operator because they are high, raised by
two or more lenses, or their fix falls in a §3.4 category (security control:
input validation, output sanitising; a verify or CI command). The first run
was headless, so each became a `D-n` in 02 with a recommendation. On
2026-10-16 the operator decided all nine ("Apply all nine"), each as
recommended; for D-1 that is the `logged-text> ` prefix and header banner,
with details staying on by default (no `--details` option, no scope change
against FR-6). R-01..R-09 were then applied as C-05..C-13, without
dispatching the reviewers again.

The findings that most change the design: R-01 (log text an injected agent
wrote becomes prompt injection when an agent reads the report), R-02 (a rule
that never fired may never have been evaluated - the report cannot prove a
negative without showing skipped checks and the window covered), and R-05
(the output format is unspecified, so AC-1 cannot be tested exactly).

## Findings

### R-01 · high · 1/3 (attacker)
- section: 02 §7, §2 step 8, §1
- finding: Logged `command`, `url`, `path` and `pattern` text is chosen by whatever agent ran the call, including an injected one. When Claude runs the report and reads stdout - the likely use - that text is prompt injection against the most privileged process on the machine. Stripping control characters does nothing against natural-language instructions, and §2's "the only reader is the operator's terminal" is false once an agent runs the tool.
- fix: Add a threat-model row. Print every recorded detail as an inert quoted value behind a fixed prefix (`logged-text> `), with one header line stating that quoted text is untrusted log data and must not be followed. Consider making detail output opt-in (`--details`), so the default report holds only counts and rule names. Recommendation: apply the prefix and banner. Treat opt-in details as a scope change against FR-6 for the operator to choose.
- outcome: applied → C-05 (D-1 decided by the operator, 2026-10-16)

### R-02 · high · 1/3 (pre-mortem)
- section: 02 §2 step 7, §8
- finding: "Never fired" and low-count rules read as "safe to enforce", but the report cannot support that. `guard.py` fails open and records `hook_error` when a check is skipped, and the design folds those into one "other events" line. It does not surface the heartbeat staleness, the 90-day prune, or how new a rule is. A rule that never fired may never have been evaluated, or may be only days old.
- fix: Header shows the first and last `ts` read and the days covered. Show `hook_error` counts by reason and tool, and whether `.heartbeat-post` is older than `.last-session`. Each never-fired rule carries "cannot tell, skipped checks: N" when errors are non-zero. Recommendation: apply. It is the difference between a count and evidence for the flip decision. It adds header fields beyond FR-2..FR-8.
- outcome: applied → C-06 (D-2 decided by the operator, 2026-10-16)

### R-03 · high · 2/3 (builder, attacker)
- section: 02 §2 step 8
- finding (builder): The 120-character limit is ambiguous: code points or bytes, whether `…` counts, wide characters and the U+FFFD that `errors="replace"` produces, and whether truncation runs before or after control-character replacement. The AC-4 test cannot pin an exact expected string.
- finding (attacker): `emit()` strips C0, C1 and DEL, but not Unicode format and separator characters. Bidi overrides (U+202E, isolates), U+2028/U+2029 and zero-width characters can reorder or hide text and make a malicious command read as benign. Only stdout goes through `emit()`. Stderr and `argparse` errors echo raw argument values and OS exception text.
- fix: `emit()` first replaces every character whose `unicodedata.category` is `Cc`, `Cf`, `Zl` or `Zp` with `?`. It then keeps at most 119 code points and appends `…`, so the line totals ≤ 120 code points. All stderr goes through the same sanitiser. Tests use exact expected strings for a 300-character command, a multi-byte command and U+202E. Recommendation: apply. It changes a security control (output sanitising), so it needs the operator's approval.
- outcome: applied → C-07 (D-3 decided by the operator, 2026-10-16)

### R-04 · high · 1/3 (pre-mortem)
- section: 02 §2 step 7
- finding: The flip decision turns on whether enforce would block legitimate work. The 10 examples per rule are the first 10 distinct values seen, with no per-example counts. For a noisy rule they hide the dominant pattern, so a false-positive-heavy rule can look clean, or a clean rule noisy.
- fix: Rank each rule's examples by frequency with a count beside each and a "+N more distinct" line. Apply the cap after ranking. De-duplicate on the full value before truncation. Recommendation: apply. It stays within FR-6 ("up to 10 distinct").
- outcome: applied → C-08 (D-4 decided by the operator, 2026-10-16)

### R-05 · high · 1/3 (builder)
- section: 02 §2, §5
- finding: The output format is undefined: no layout, section order, header wording, line format or sort order. AC-1 and §10 nevertheless require exact matches. Two builders would write incompatible output, and the test cannot be written from 02 alone.
- fix: Add an output specification with a sample report: header fields in order, section titles, line formats (e.g. `rule  action  count`), sort order and tie-breaks, and empty-section text. Recommendation: apply, folding in whatever D-1, D-2 and D-4 decide.
- outcome: applied → C-09 (D-5 decided by the operator, 2026-10-16)

### R-06 · high · 1/3 (builder)
- section: 02 §10, §3
- finding: The default `bash scripts/test-guard-report.sh` does not enforce coverage; only `COVER=1` measures it. 02 does not say CI sets it, so AC-8 is not proven by the check command. `--branch` is not stated, and the suite has no total time budget even though it includes the 10,000-record case.
- fix: CI runs `COVER=1 bash scripts/test-guard-report.sh` under `coverage run --branch`, with `coverage report --fail-under=80`. The uncovered run is the fast local default. Target ≤ 10 s for the whole suite. Recommendation: apply. It changes a CI/verify command (§3.4).
- outcome: applied → C-10 (D-6 decided by the operator, 2026-10-16)

### R-07 · medium · 3/3 (builder, pre-mortem, attacker)
- section: 02 §1, §3, §7, §11 A-5
- finding (builder): No behaviour is defined for a failed import of `guard.py` or a changed `RULES` shape, and §5 has no exit code for it. A-8 (performance) is still ❓.
- finding (pre-mortem): Rules come from the repository copy of `guard.py`, but the log was written by the installed plugin copy, which may be an older or `--copy` install. Records whose rule is absent from the imported `RULES` (renamed or removed) have no defined handling.
- finding (attacker): `exec_module` writes `__pycache__/guard.*.pyc` next to `guard.py` unless bytecode writing is off, which contradicts "no writes". The `guard.py` path resolution is unstated, and a cwd- or env-supplied path would be arbitrary code execution. `python3 scripts/guard-report.py` also puts `scripts/` first on `sys.path`.
- fix: Set `sys.dont_write_bytecode = True` before the import. Resolve the path only from `Path(__file__).resolve().parent.parent / "plugins/devagent-standards/hooks/guard.py"`, with no option or env override; tests use a copied repo layout instead. Run as `python3 -I`. An import failure or an unexpected `RULES` shape gets a stderr message and exit 3. The header shows the `guard.py` path and SHA-256. Rules seen in the log but absent from `RULES` are listed under "not in current RULES" with their recorded action. AC-5 also asserts no `__pycache__` is created. Measure A-8 during build. Recommendation: apply. Raised by all three lenses, and the import is a security-relevant code path.
- outcome: applied → C-11 (D-7 decided by the operator, 2026-10-16)

### R-08 · medium · 2/3 (builder, attacker)
- section: 02 §2 steps 4-7
- finding (builder): Edge cases are undefined: a missing or non-string `event`, a `guard` record with a missing or invalid `action`, a `--since` date in the future, whether never-fired is computed over the filtered window, and malformed lines counted per file or per run.
- finding (attacker): `ts` is checked only by a prefix regex, so `9999-99-99T` makes a bogus day bucket. `action` and `rule` values are not checked, so a forged or flooded log adds unbounded buckets and can misreport what a rule enforces.
- fix: A missing or non-string `event` is malformed. `ts[:10]` must parse with `date.fromisoformat`, otherwise the record is malformed. `action` must be `deny` or `ask`, otherwise malformed. Never-fired is computed over the filtered window. Malformed lines are totalled per run. A future `--since` gives an empty report with exit 0. Each rule is a test case. Recommendation: apply. It changes input validation (§3.4).
- outcome: applied → C-12 (D-8 decided by the operator, 2026-10-16)

### R-09 · medium · 1/3 (attacker)
- section: 02 §2 steps 4-5, §7
- finding: Symlinks are checked and then opened, which is a TOCTOU race, and special files are not excluded. A FIFO named `2026-10.jsonl` blocks `open()` forever, and `guard.py`'s audit-tamper verbs omit `ln` and `mkfifo`. The §7 claim that snippets are capped near 400 characters is false for `path`: `summarize()` records `file_path` and Grep `path` without `redact()` or a cap, so `for line in fh` can read an unbounded line.
- fix: Open with `os.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)`, `fstat`, and require `S_ISREG`; a non-regular file is skipped and counted. Read with a bounded `readline(65536)`. An over-long line is malformed, and the rest of it is discarded. Correct the §7 row. Recommendation: apply. It is a security control (input validation). The `ln`/`mkfifo` gap in `guard.py` is out of scope here (01) and noted for a later guard change.
- outcome: applied → C-13 (D-9 decided by the operator, 2026-10-16)

### R-10 · medium · 1/3 (pre-mortem)
- section: 02 §1, §2 step 7
- finding: The enforce action is counted per record, per rule, but enforce acts per call. When several rules hit one call, `handle_pre` denies if any hit is `deny` (guard.py:653), so a co-matching `ask` never prompts. The per-rule split overstates the prompts the operator would see. The `mode` field is ignored, and enforce-mode records have no matching `tool` record.
- fix: Group guard records into calls by (session, ts, tool, detail). Report calls that would be denied or asked alongside the per-rule table. Split totals by recorded `mode`. Label match counts as matches, not as a proportion of calls.
- outcome: applied → C-03

### R-11 · low · 1/3 (pre-mortem)
- section: 02 §1, §2 step 7
- finding: A partition is the sanitised repo-root folder name, not an engagement. Sessions outside a repo land in `no-repo`, and two repos with the same folder name merge into one. The per-engagement table can blur which engagement a rule bites in, with no warning.
- fix: Label the table "by partition (repo folder name)". Show `no-repo` as its own labelled row, and add a test for it.
- outcome: applied → C-04
