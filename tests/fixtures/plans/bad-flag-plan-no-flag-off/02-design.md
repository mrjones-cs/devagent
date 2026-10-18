---
format: delivery-plan/1
feature: bad-flag-plan-no-flag-off
step: 02-design
status: reviewed
date: 2026-10-02
generator: delivery@v1.4.0
reads: 01-requirements.md, 03-research.md, 04-review.md
tier: M
personal_data: false
calls_model: false
has_ui: false
flagged: true
---

# Design: fixture feature

An example inside a code fence is not part of the document's grammar:

```
| not a table
### T-99 [?] not a task
```

## 12. Assumptions to verify

| # | Assumption | Load-bearing | Status |
|---|---|---|---|
| A-01 | The runtime is supported | yes | ✅ |
| A-02 | The provider version is current | yes | 🔄 |

## 13. Operator decisions

| ID | Decision | Outcome |
|---|---|---|
| D-1 | Where files live | Decided (C-01) |

## Change log

| ID | Date | Source | Section | Change |
|---|---|---|---|---|
| C-01 | 2026-10-02 | operator | §1 | Files live in the repo |
| C-02 | 2026-10-02 | research A-02, R-01 | §2 | Provider pinned |
| C-03 | 2026-10-03 | render check | §3 | Diagram redrawn |
| C-04 | 2026-10-05 | T-01 | §4 | Build departure recorded |
