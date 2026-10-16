---
format: delivery-plan/1
feature: guard-report
generator: delivery@v1.4.0
step: 03-research
status: draft
date: 2026-10-16
reads: 01-requirements.md, 02-design.md
---

# Research: Guard report

Tier M: only the six load-bearing assumptions were checked. Every one is a
fact about this repository's own code or the local Python interpreter, so each
was confirmed by a live check run today rather than a web search; no query
was sent to any outside service. The live audit log was inspected for record
shape only (event types and key names, counted), never for values. The two
non-load-bearing rows are left unverified as tier M allows; A-7 was observed
in passing.

## Assumptions

| # | Assumption | Status | Current truth | Official source | Checked | Engine |
|---|---|---|---|---|---|---|
| A-1 | `guard` records carry `ts`, `tool`, `rule`, `action` and one detail field | ✅ | `handle_pre` writes `tool`, `rule`, `action`, `mode` plus `summarize()` output; live log shape has `guard` records with `path` or `command`. For tools `summarize()` does not special-case (e.g. `mcp__playwright__browser_navigate`) the detail is `input_keys`, a list, not a string | live: `grep -n 'rec.update' plugins/devagent-standards/hooks/guard.py` (line 646) and a key-shape count of `~/.claude/devagent-audit/*/*.jsonl` | 2026-10-16 | manual |
| A-2 | Each `tool` record is one completed tool call | ✅ | `handle_post` (PostToolUse) writes exactly one `event: "tool"` record per call; a call denied in enforce mode never reaches PostToolUse, so it has a `guard` record but no `tool` record | live: `grep -n 'base_record(data, "tool")' plugins/devagent-standards/hooks/guard.py` (line 675) | 2026-10-16 | manual |
| A-3 | `ts` is UTC `YYYY-MM-DDTHH:MM:SSZ` | ✅ | `base_record` and the `hook_error` path both use `time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())` | live: `grep -n '"ts": time.strftime' plugins/devagent-standards/hooks/guard.py` (lines 541, 707) | 2026-10-16 | manual |
| A-4 | Layout `AUDIT_DIR/<partition>/YYYY-MM.jsonl`, partition alphabet `[A-Za-z0-9._-]`, dot-files at root | ✅ | Confirmed (lines 530, 533, 522). The root also holds `search.jsonl`, written by `plugins/delivery/scripts/web-search` (`AUDIT_REL`); it is not a partition and not a `YYYY-MM.jsonl` file, so the design's filter already excludes it | live: `grep -n 'AUDIT_REL' plugins/delivery/scripts/web-search` and `find ~/.claude/devagent-audit -name search.jsonl` | 2026-10-16 | manual |
| A-5 | Importing `guard.py` by path has no side effects and exposes `RULES` | ✅ | Import under a throwaway `HOME` wrote 0 files and printed nothing; `RULES` is `{tool: [(rule, action, check)]}` with 10 distinct rules across 12 tools | live: `HOME=$(mktemp -d) python3 -I -c 'importlib.util.spec_from_file_location(...)'` then `find $HOME -mindepth 1` | 2026-10-16 | manual |
| A-6 | `argparse` exits 2 on an unknown option and on `parser.error()` | ✅ | Both exit 2 on Python 3.14.6 | live: `python3 -I -c "import argparse; ...parse_args(['--bogus'])"; echo $?` | 2026-10-16 | manual |
| A-7 | `uv ... coverage==7.16.2` works locally | ✅ | `Coverage.py, version 7.16.2 with C extension` | live: `uv run -q --no-project --with coverage==7.16.2 python -m coverage --version` | 2026-10-16 | manual |

## Changes nobody asked about (bounded look)

Tier M: no bounded look.

| # | Finding | Status | Current truth | Official source | Checked | Engine |
|---|---|---|---|---|---|---|

## Queries sent

- None: every row was confirmed by a live check.

## Design changes recommended

- A-1: section 2 step 7 - a record whose detail is `input_keys` (or absent)
  contributes the placeholder `(no detail recorded)` rather than a list.
- A-2: section 1 - state that in enforce mode a denied call has a `guard`
  record but no `tool` record, so matches can exceed the calls they belong to.
