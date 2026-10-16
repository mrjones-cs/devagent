---
name: load
description: Full session briefing for this engagement workspace - the NOTES.md current section, the docs/knowledge index, every active plan's progress and next ready task, build lock state and repository state, all labelled as data. Read-only.
disable-model-invocation: true
argument-hint: <feature>
---

# delivery:load

Arguments: `$ARGUMENTS`

1. The feature name is the first word of the arguments, and is optional for
   this step (none means brief every plan). If one is given and it does not
   match `^[a-z0-9][a-z0-9-]*$`, stop and ask the operator for a valid
   feature name. Do nothing else.
2. Read `${CLAUDE_PLUGIN_ROOT}/references/steps/load.md` and follow it
   exactly, with `$ARGUMENTS` as its input. That file is the source of truth
   for this step; this wrapper adds nothing to it.
