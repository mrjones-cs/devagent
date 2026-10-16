# Example: `guard-report`, built with the delivery workflow

A complete, real record of one feature taken through the delivery workflow
end to end: `load → brainstorm → plan (design, research, spec-panel) →
workflow → build → save`. The feature itself is `scripts/guard-report.py` in
this repository, a read-only summary of the guard's audit log.

It ran as a **pilot**, one headless `claude -p` session per step, at tier M
(the operator overrode tier S so `plan` would chain every step). Things worth
reading for:

- `04-review.md`: three blind reviewers (builder, attacker, pre-mortem)
  found 15 issues, merged to 11; nine went to the operator as decisions.
- `02-design.md`: the design after research and review were applied, with
  its change log.
- `05-implementation.md`: five tasks, each ticked only with evidence that
  `run-verify` recorded in `evidence/`. The build was killed mid-task on
  purpose and resumed in a new session; the protocol reconciled it.
- Measured cost of the whole run: see `docs/DESIGN.md` §12.

**Published copy.** The record is unchanged except that the project's own
names were replaced with DevAgent's, and one absolute path in
`evidence/T-04.log` was rewritten as `<repo>` (its sha256 in
`05-implementation.md` was recomputed to match). `check-plan.py` passes:

```bash
python3 plugins/delivery/scripts/check-plan.py examples/guard-report
```

As an example outside `docs/plans/`, the commit rule (one `T-nn:` commit per
ticked task) is not applied; the grammar, evidence and hash rules are.
