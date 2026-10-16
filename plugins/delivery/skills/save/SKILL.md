---
name: save
description: Closes a session - updates NOTES.md, writes project lessons to docs/knowledge, sets the newest plan file's status, and reports uncommitted work, orphaned worktrees, locks and plan drift. With --handover exports the leak-reviewed deliverable; with --closeout inventories every copy.
disable-model-invocation: true
argument-hint: <feature> [--handover|--closeout]
---

# delivery:save

Arguments: `$ARGUMENTS`

1. Take the first word of the arguments as the feature name. If it is missing
   or does not match `^[a-z0-9][a-z0-9-]*$`, stop and ask the operator for a
   valid feature name. Anything after it may only be `--handover` or
   `--closeout`, never both; otherwise stop. Do nothing else.
2. Read `${CLAUDE_PLUGIN_ROOT}/references/steps/save.md` and follow it
   exactly, with `$ARGUMENTS` as its input. That file is the source of truth
   for this step; this wrapper adds nothing to it.
