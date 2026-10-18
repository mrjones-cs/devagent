# Making DevAgent yours

DevAgent ships generic rules. Your organisation's specifics (its name, its
registers, its clients, its cloud accounts) belong in **your** copy of the
rules, which can live in a private repository you control.

## 1. Fill in the template

`./install.sh` copied `templates/CLAUDE.md` to `~/.claude/CLAUDE.md`. Edit it:

1. **ORGANISATION block.** Your legal name (used for the copyright notice on
   your own documents, never on customer deliverables), and where your vendor
   register and security audit log live. The skills read these values from
   here rather than naming an organisation.
2. **Every `[PLACEHOLDER]`.** `grep -n '\[' ~/.claude/CLAUDE.md` finds them.
3. **Delete what does not apply.** A rule you will never follow is noise
   that dilutes the ones you will.

## 2. Keep your rules in your own repository

A private repository is the better home: history, review, and the same rules
on every machine. Put your `CLAUDE.md` (and optionally a `clients.local.md`,
see below) in it, then link it:

```bash
./install.sh --rules ~/my-rules/CLAUDE.md          # symlink: git pull updates every machine
./install.sh --rules ~/my-rules/CLAUDE.md --copy   # real copy: cannot dangle, but drifts
```

`./install.sh --check` exits 1 if the link is dangling, which is the one
failure that is otherwise silent: every rule simply stops loading. Put it in
your shell profile or onboarding checklist.

## 3. What must stay resident

Some rules only work if they are loaded on every turn, because the moment
they apply is exactly the moment a skill would not be invoked. Before moving
anything out of `CLAUDE.md`, read [ARCHITECTURE.md](ARCHITECTURE.md) §1. In
short, keep resident:

- toolchain security and prompt-injection rules (the attack arrives before
  any trigger),
- customer confidentiality and content constraints,
- verification ("prove it before you say done"),
- leaked-credential response,
- and one **stub** per skill, which is what makes a skill load reliably.

## 4. The client brand list

`~/.claude/clients.local.md` (mode 600, never committed) is optional. The
rules already forbid putting **any** client name in an exported artifact
without explicit authorization; the list only names brands for which even
explicit authorization is not enough. An empty list is a safe state. If your
rules repository keeps a `clients.local.md` beside its `CLAUDE.md`,
`install.sh --rules` links it too. Keep that repository private.

## 5. Adding a standard of your own

1. Create `plugins/devagent-standards/skills/<name>/SKILL.md` with front
   matter `name` and a `description` that says **when** to use it (it is
   matched against the task, so lead with the trigger).
2. Add a stub for it to your `CLAUDE.md` under DETAILED STANDARDS:
   ``**`devagent-standards:<name>`** — summary. → Invoke when …``.
3. Run `python3 scripts/check-skills.py`. It fails on a skill with no stub, a
   stub for a missing skill, a dead path reference, or a stale count in the
   prose.

Prefer forking the repository for standards that are specific to you, and
contributing upstream the ones that would help anyone.

## 6. Tuning the guard

- **Review what fired:** `python3 -I scripts/guard-report.py`.
- **A false positive** is a bug in a rule: fix the rule and add a test case
  to `scripts/test-hooks.sh` (each rule has cases that must fire and benign
  look-alikes that must not). Never reword a command to slip past a rule.
- **Roll back locally:** `DEVAGENT_GUARD_MODE=warn` in the environment.
- **Rule list:** the `RULES` table in `plugins/devagent-standards/hooks/guard.py`.

## 7. Delivery workflow settings

- **Deny-list for research queries:** `.delivery/deny-list` in a project, one
  term per line (client names, project code names). Gitignore it. The search
  script refuses any query containing a listed term.
- **Pins:** `plugins/delivery/PINS.md` records every pinned version, why, and
  when it was last reviewed; `check-skills.py` asserts each matches where it
  is set. Re-pin deliberately, never drift to latest.
- **Review lenses:** `plugins/delivery/references/lenses/`, one file per
  reviewer perspective (front matter `slug`, `standards`, `when`, `model`).

## 8. Web search

Optional; see the README and `infra/terraform/web-search/`. Without it,
research confirms facts on official pages directly.

## 9. Feature flags

The delivery workflow can plan a feature that ships behind a flag, and plan
the flag's removal from the start.

**DevAgent ships no flag runtime and integrates with no flag vendor.** Your
own flag system stays in charge: a vendor SDK, a parameter store, or a config
file in the client's code. DevAgent adds a planning convention, a checker rule,
a report, a build hold and a standard; nothing it adds runs in the system you
deliver.

**In the design.** The design step (run by `/delivery:plan`) sets
`flagged: true` in `02-design.md` when the feature ships behind a flag, and names the flag system
and the flag with its rollout. The `devagent-standards:feature-flags` skill
sets the rules for using it: default off, an owner and a removal date for every
flag, server-side evaluation for anything security-relevant, security controls
never flag-gated, and a hosted flag service treated as a vendor.

**In the plan.** The workflow step copies `flagged` into
`05-implementation.md` and writes three kinds of task for each flag:

- the **add task**, first: it wires the flag into your flag system, **off by
  default**;
- every **guarded task** (each task that depends on the add task) carries
  `- flag on:` and `- flag off:`, saying what is observed in each state, and
  its verify exercises both;
- the **remove task**, last: it deletes the flag and the code path it
  retired, and names a client-side owner role (`flag_owner`, a role, not a
  person) and a date (`remove_by`).

An add and remove pair in the 05 grammar:

```
### T-02 [ ] Add flag new-search, off by default
- depends: T-01
- flag: add new-search
- files: src/flags.py
- acceptance: the flag exists and is off by default
- verify: `npm test -- flags`
- timeout: 5m

### T-03 [ ] Search behind new-search
- depends: T-02
- files: src/search.ts, test/search.test.ts
- acceptance: the new search answers when the flag is on
- flag on: the new search endpoint returns results
- flag off: the old search answers and the new endpoint returns 404
- verify: `npm test -- search`
- timeout: 10m

### T-04 [ ] Remove flag new-search
- depends: T-01, T-02, T-03
- flag: remove new-search
- flag_owner: client platform lead
- remove_by: 2027-01-31
- files: src/flags.py, src/search.ts, test/search.test.ts
- acceptance: the old search path and the flag are gone
- verify: `npm test -- search`
- timeout: 10m
```

`check-plan.py` (rule `flag-plan`) fails a flagged plan with no flag task, a
flag without exactly one add and one remove task, a remove task with no owner
or no real date, a task not ordered against the add task, a remove task that
does not come after the feature work, or a guarded task missing either check.
A date in the past never fails it.

**Checking flags.** `python3 plugins/delivery/scripts/check-plan.py --flags
docs/plans/<feature>` (or `--flags --all`) prints one line per flag with its
owner, removal date and status: `live`, `overdue`, `removed` or
`inconsistent`, and `beyond a year` when the date is more than a year after
the plan.

**Building.** `/delivery:build <feature>` builds everything except remove
tasks, which it holds and lists as `held for rollout`. Once the rollout is
finished, `/delivery:build <feature> --remove-flags` runs them.

**At handover.** A remove task may still be open at delivery.
`/delivery:save <feature> --handover` lists every flag not yet removed in the
handover manifest, with its client-side owner and removal date, and states
that the client owns removing it after delivery.
