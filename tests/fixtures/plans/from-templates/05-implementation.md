---
format: delivery-plan/1
feature: sample-feature
generator: delivery@v0.1.0
step: 05-implementation
status: draft
date: 2026-10-14
reads: 01-requirements.md, 02-design.md, 03-research.md, 04-review.md
branch: main
base: abc1234
verify_allowed:
  - python3 -m unittest
# manual_evidence: [T-01]   # optional: tasks whose evidence was written by hand
---

# Implementation plan: Sample feature

<!-- One paragraph: what is built, tier, and which design version this plan was cut from. -->
Sample text for plan summary

## How to read this
- Status: `[ ]` todo, `[~]` in progress, `[x]` done, `[!]` blocked.
- `verify` is the single command that proves a task and must appear in `verify_allowed`, with no shell operators.
- Evidence is written only by `run-verify`.

## Quality gates (apply to every task)
<!-- Requirements every task must meet before it is marked done. Keep to checks that can fail. -->

| Gate | Requirement | Source |
|---|---|---|
| G-1 | The check command passes after the task | VERIFICATION |

## Phase 1 — Foundations
<!-- One block per task, in exactly this grammar. depends is "none" or "T-nn, T-nn". timeout is <n>s, <n>m or <n>h.
     Add evidence only when the task is [x], and only via run-verify. -->

### T-01 [ ] Sample text for task title
- depends: none
- files: src/app.py, tests/test_app.py
- acceptance: Sample text for observable result
- verify: `python3 -m unittest`
- timeout: 10m
