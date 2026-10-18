---
format: delivery-plan/1
feature: {{feature}}
generator: delivery@{{release_tag}}
step: 05-implementation
status: draft
date: {{YYYY-MM-DD}}
reads: 01-requirements.md, 02-design.md, 03-research.md, 04-review.md
branch: {{branch}}
base: {{base_commit}}
flagged: {{true_or_false}}
verify_allowed:
  - {{verify_command}}
# manual_evidence: [T-01]   # optional: tasks whose evidence was written by hand
---

# Implementation plan: {{feature_title}}

<!-- One paragraph: what is built, tier, and which design version this plan was cut from. -->
{{plan_summary}}

## How to read this
- Status: `[ ]` todo, `[~]` in progress, `[x]` done, `[!]` blocked.
- `verify` is the single command that proves a task and must appear in `verify_allowed`, with no shell operators.
- Evidence is written only by `run-verify`.

## Quality gates (apply to every task)
<!-- Requirements every task must meet before it is marked done. Keep to checks that can fail. -->

| Gate | Requirement | Source |
|---|---|---|
| G-1 | {{gate_requirement}} | {{gate_source}} |

## Phase 1 — {{phase_name}}
<!-- One block per task, in exactly this grammar. depends is "none" or "T-nn, T-nn". timeout is <n>s, <n>m or <n>h.
     Add evidence only when the task is [x], and only via run-verify.
     When flagged is true, each flag adds these bullets to task blocks, each key once per task:
       the add task, first:        - flag: add <name>
       every task depending on it: - flag on: <what is observed with the flag on>
                                   - flag off: <what is observed with the flag off>
       the remove task, last:      - flag: remove <name>
                                   - flag_owner: <client-side role, not a person>
                                   - remove_by: YYYY-MM-DD -->

### T-01 [ ] {{task_title}}
- depends: none
- files: {{file_paths}}
- acceptance: {{observable_result}}
- verify: `{{verify_command}}`
- timeout: 10m
