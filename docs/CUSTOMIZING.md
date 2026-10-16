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
