---
name: workflow
description: Writes a feature's 05-implementation.md from the final design - small tasks with files, acceptance, a single allowlisted verify command and a timeout - refusing while a decision is open or a load-bearing assumption is unverified.
disable-model-invocation: true
argument-hint: <feature>
---

# delivery:workflow

Arguments: `$ARGUMENTS`

1. Take the first word of the arguments as the feature name. If it is missing
   or does not match `^[a-z0-9][a-z0-9-]*$`, stop and ask the operator for a
   valid feature name. Do nothing else.
2. Read `${CLAUDE_PLUGIN_ROOT}/references/steps/workflow.md` and follow it
   exactly, with `$ARGUMENTS` as its input. That file is the source of truth
   for this step; this wrapper adds nothing to it.
