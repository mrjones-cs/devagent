---
format: delivery-plan/1
feature: feature-flags
generator: delivery@1.0.1
step: 04-review
status: draft
date: 2026-10-17
reads: 01-requirements.md, 02-design.md, 03-research.md
classification: client-confidential
---

# Review: Feature flags

## Summary

Tier M panel with three lenses: builder, attacker and pre-mortem. Each ran on
Sonnet as a fresh reviewer, blind to the others. 02 was passed by path, with
an instruction to read it whole, rather than inlined. 01's acceptance
criteria and 03's ⛔ row were inlined. The lenses raised 15 findings, which
merged into 11: 5 high, 4 medium and 2 low.

Six findings went to the operator because they were high, raised by two or
more lenses, or changed a security control. The operator approved each as
recommended on 2026-10-17 (D-1 to D-4). The other five were applied
directly. Nothing was rejected, so the rejection rate is 0% for each lens.

The findings that most changed the design:
- the parser's first-key-wins behaviour (R-01);
- removal falling after delivery (R-04);
- central output sanitising (R-05).

## Findings

### R-01 · high · 3/3 (attacker, builder, pre-mortem)
- section: 02 §1.2
- finding: `bullets()` keeps the first occurrence of each key (`setdefault`), so a second `- flag:` line in a task, or `flag_owner` / `remove_by` passed as `owner` sub-fields, is never seen. Pairing and duplicate checks can be bypassed, and the multi-flag claim is not backed by the parser.
- original (attacker): hidden `- flag: remove b` and `owner` sub-fields satisfy or evade the rule.
- original (pre-mortem): A-1 at risk; condition 5 cannot see what the parser dropped.
- original (builder): one task cannot carry two flag operations, and duplicate keys are undefined.
- fix: scan raw task lines for the flag keys; one `flag:` bullet per task; fail on repeated keys and on flag keys inside `owner` sub-fields; fixtures for both.
- outcome: applied → C-05

### R-02 · high · 2/3 (builder, pre-mortem)
- section: 02 §10
- finding: there is no single check command and no stated run time, and AC-6 is only proven after the first push, so a late `check-skills` or fixture failure lands at the end.
- original (builder): name one aggregate command and its measured run time, and use CI only to confirm.
- original (pre-mortem): the estimate is optimistic; run the full suite list before the integrated push.
- fix: `scripts/check-all.sh` as the whole-repository gate and final verify, with its run time measured and the task estimate revised.
- outcome: applied → C-06

### R-03 · high · 1/3 (builder)
- section: 02 §1.2
- finding: the ordering conditions contradict each other when a plan has two flags (one flag's add task is a "non-remove task" for the other), and "between" is not defined.
- fix: define every condition per flag in graph terms; add fixtures for two flags and for a setup task.
- outcome: applied → C-07

### R-04 · high · 1/3 (pre-mortem)
- section: 02 §1.5
- finding: removal follows gradual rollout, usually after delivery, but the remove task had to be last, so the plan either never closes or the flag is removed before rollout. After handover nobody is accountable for the removal.
- original (pre-mortem, second finding): flag debt after handover has no accountable owner on the client side.
- fix: `build-ready` holds remove tasks until `--remove-flags`; 05 may be complete with only held remove tasks open; the handover manifest names a client-side owner and date; the skill and `engagement-closeout` say the client owns removal; residual risk accepted in §7.
- outcome: applied → C-08

### R-05 · high · 1/3 (attacker)
- section: 02 §1.4
- finding: only the `--flags` owner was to be sanitised, but normal failure lines also echo untrusted plan values, so ESC, bidi overrides or a newline can reach the terminal and the transcript, or forge a `file:line: [rule]` line.
- fix: sanitise centrally in `Failure.render` and the `--flags` printer, with a length cap and tests.
- outcome: applied → C-09

### R-06 · medium · 2/3 (builder, pre-mortem)
- section: 02 §1.2
- finding: checking for the words `flag on` and `flag off` in the acceptance text is weak, because they can appear in an unrelated sentence. AC-3's model-written part was observed only informally.
- fix: required `- flag on:` and `- flag off:` bullets on every guarded task; the AC-3 `workflow` run becomes a named step with an expected result.
- outcome: applied → C-10

### R-07 · medium · 1/3 (attacker)
- section: 02 §1.3
- finding: `removed` trusted the remove task's `[x]` alone, and a far-future `remove_by` keeps a flag `live` forever.
- fix: `removed` only when both tasks are `[x]` in a folder that passes every check; `inconsistent` for a removal with no add; a `beyond a year` marker.
- outcome: applied → C-11

### R-08 · medium · 1/3 (builder)
- section: 02 §1.3
- finding: `--flags` output for `--all`, failing folders, task states other than `[x]`, and what `save` does on a non-zero exit were undefined.
- fix: exact line format with the feature prefix, a status for every state, exit 1 for a failing folder, and the `save` handling.
- outcome: applied → C-12

### R-09 · medium · 1/3 (attacker)
- section: 02 §1.7
- finding: the skill covered server-side evaluation for access but not client-side exposure: SDK keys and bootstrap payloads that return every flag, an open flag console, and unsigned webhooks.
- fix: add rules for session-scoped evaluation, public SDK keys, MFA and least privilege on the console, signed webhooks, and no customer identifiers in keys.
- outcome: applied → C-13

### R-10 · low · 1/3 (attacker)
- section: 02 §1.7
- finding: nothing said a flag must never disable a security control, and the kill switch had no defined authority or failure default.
- fix: security controls are never flag-gated; flag stores are writable only by audited principals; the kill switch fails off with a built-in default.
- outcome: applied → C-14

### R-11 · low · 1/3 (builder)
- section: 02 §10
- finding: the 13 → 14 skill-count update was not listed by file.
- fix: list each file and line.
- outcome: applied → C-15
