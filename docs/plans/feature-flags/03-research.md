---
format: delivery-plan/1
feature: feature-flags
generator: delivery@1.0.1
step: 03-research
status: draft
date: 2026-10-17
reads: 01-requirements.md, 02-design.md
---

# Research: Feature flags

Tier M: the three load-bearing assumptions were checked. Each is a fact about
this repository or the installed plugin, so each was confirmed by a live
check run today; no query was sent to any search service. Two
non-load-bearing rows were checked as well because the checks were cheap:
A-5 is wrong, confirmed on the official Python documentation, and A-4 is
left unverified as tier M allows. No bounded look at tier M.

## Assumptions

| # | Assumption | Status | Current truth | Official source | Checked | Engine |
|---|---|---|---|---|---|---|
| A-1 | The task bullet parser accepts `flag`, `flag_owner` and `remove_by` keys unchanged | ✅ | `BULLET = ^- ([a-z][a-z _]*):\s*(.*)$` (line 82) matches all three keys; `bullets()` gives special handling only to `owner`, so `flag_owner` is not split | live: `grep -n '^BULLET' plugins/delivery/scripts/check-plan.py` and a `python3 -I` match of the three sample bullets | 2026-10-17 | manual |
| A-2 | A new `skills/<name>/SKILL.md` directory is discovered without listing it in `plugin.json` | ✅ | `plugins/devagent-standards/.claude-plugin/plugin.json` has no skills key, yet all 13 installed skill directories are discovered and invocable in this session (`devagent-standards:stack-selection` was invoked by the design step) | live: `cat plugins/devagent-standards/.claude-plugin/plugin.json` and `ls ~/.claude/plugins/cache/devagent/devagent-standards/1.0.1/skills` | 2026-10-17 | manual |
| A-3 | No existing fixture or example carries `flagged` or a flag bullet | ✅ | No match in `tests/fixtures/`, `examples/` or `docs/plans/` outside this plan | live: `grep -rlE '^flagged:\|^- flag(_owner)?:\|^- remove_by:' tests/fixtures examples docs/plans` (exit 1, no match) | 2026-10-17 | manual |
| A-5 | `date.fromisoformat` rejects every malformed `remove_by` | ⛔ | Since Python 3.11 it accepts any ISO 8601 date except reduced precision, extended and ordinal forms, so `20270131` and `2027-W01-1` both parse. Live on 3.14.6: `20270131` accepted; `2027-02-30`, `2027-1-31` and ` 2027-01-31` rejected. `remove_by` needs the existing `DATE` pattern (`^\d{4}-\d{2}-\d{2}$`) first, then `fromisoformat` for calendar validity | https://docs.python.org/3/library/datetime.html | 2026-10-17 | official-page |

## Changes nobody asked about (bounded look)

None: tier M has no bounded look.

| # | Finding | Status | Current truth | Official source | Checked | Engine |
|---|---|---|---|---|---|---|

## Queries sent
- none - every row was a live check or a direct official page; no search service was used

## Design changes recommended
- A-5: in 02 §1 rule condition 2, validate `remove_by` with the existing
  `DATE` pattern and then `date.fromisoformat`, and add a `20270131` case to
  the §10 bad-date fixtures. This touches input validation, a
  security-relevant category (DESIGN §3.4); the operator approved it on
  2026-10-17 and it is applied as C-01.
