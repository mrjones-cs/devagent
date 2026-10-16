---
name: plan
description: Runs the planning chain for a feature - design, research, spec-panel, workflow - in order, resuming at the first missing plan file, pausing only for decisions flagged for the operator, and ending with a summary.
disable-model-invocation: true
argument-hint: <feature>
---

# delivery:plan

Arguments: `$ARGUMENTS`

1. Take the first word of the arguments as the feature name. If it is missing
   or does not match `^[a-z0-9][a-z0-9-]*$`, stop and ask the operator for a
   valid feature name. Do nothing else.
2. Read `${CLAUDE_PLUGIN_ROOT}/references/steps/plan.md` and follow it
   exactly, with `$ARGUMENTS` as its input. That file is the source of truth
   for this step; this wrapper adds nothing to it.
