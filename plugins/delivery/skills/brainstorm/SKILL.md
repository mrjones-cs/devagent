---
name: brainstorm
description: Interactive requirements discovery for one feature - goals, users, data handled, client constraints and acceptance criteria. Proposes the S/M/L tier from explicit triggers, records the client AI-use position, and writes 01-requirements.md. Never designs.
disable-model-invocation: true
argument-hint: <feature>
---

# delivery:brainstorm

Arguments: `$ARGUMENTS`

1. Take the first word of the arguments as the feature name. If it is missing
   or does not match `^[a-z0-9][a-z0-9-]*$`, stop and ask the operator for a
   valid feature name. Do nothing else.
2. Read `${CLAUDE_PLUGIN_ROOT}/references/steps/brainstorm.md` and follow it
   exactly, with `$ARGUMENTS` as its input. That file is the source of truth
   for this step; this wrapper adds nothing to it.
