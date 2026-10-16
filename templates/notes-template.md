# NOTES.md Template

Copy the block below verbatim into a project's `NOTES.md` when creating one.
The protocol for reading and writing it is in the resident NOTES.md section
of `~/.claude/CLAUDE.md`. Add `NOTES.md` to `.gitignore`; do not commit it.

---

```
# Session Notes

## Goal
[One-line objective for this session]

## What We're Building
[2-3 sentences max: what this project/feature is, what it does,
 why it exists. Enough for full context recovery after compaction.]

## Current Approach
[How we're solving it: architecture, key patterns, technology
 choices. Update this when the approach changes.]

## Project Structure
- Tech stack: [languages, frameworks, key libraries]
- Entry point: `path/to/main`
- Config: `path/to/config` - [key settings]
- Build/run command: `command here`
- Test command: `command here`

## Key Files
- `path/to/file:line` - what it does / why it matters
[Files actively relevant to current work. Include line numbers
 for specific functions or sections being worked on.]

## Task List
- [x] Completed items (note what was done, not just "done")
- [ ] Pending items
- [ ] ~Cancelled items~ (note why cancelled)

## Progress Log
[Append-only log of what happened. This is the KEY section for
 context recovery. Each entry should have enough detail that you
 could resume work from that point alone.]

- HH:MM - What was done, what was learned, what's next
- HH:MM - Error encountered: `exact error message`. Root cause: X. Fix: Y.
- HH:MM - User clarified: "their exact words". Impact on approach: Z.
- HH:MM - Read `file:lines` - discovered [key finding]
- HH:MM - Modified `file:lines` - changed X to Y because Z

## Code Patterns & Snippets
[Capture key implementation patterns, function signatures, or
 solutions that would be hard to re-derive. Keep brief.]

```language
// Pattern: [what this solves]
key code snippet here
```

## Environment & Runtime State
- Running services: [ports, URLs, PIDs if relevant]
- Env vars needed: [VAR_NAME=context, not actual secrets]
- Database state: [migrations run, seed data, schema notes]
- Branch: `branch-name` (based on `parent-branch`)

## Decisions
- Decision (rationale) [timestamp or task reference]

## Failed Attempts
- What we tried → exact error or why it didn't work → what we learned
  [Include enough detail to avoid repeating the mistake]

## User Preferences & Clarifications
- Preference/clarification (when it was expressed)
[Capture the user's communication style, naming preferences,
 architectural opinions, and explicit instructions]

## Context & Gotchas
- Constraints, discovered quirks, non-obvious behaviors
- Anything that would be painful to re-learn
- Known bugs or workarounds in dependencies

## Open Questions
- Questions that haven't been resolved yet
- Things to verify or investigate later

---

# Session Archive
```
