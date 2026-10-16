---
name: design
description: Writes a feature's 02-design.md from its requirements - architecture, data classification, threat model, cost, observability, the personal_data, calls_model and has_ui flags, and load-bearing assumptions to verify - applying each standard the design touches.
disable-model-invocation: true
argument-hint: <feature>
---

# delivery:design

Arguments: `$ARGUMENTS`

1. Take the first word of the arguments as the feature name. If it is missing
   or does not match `^[a-z0-9][a-z0-9-]*$`, stop and ask the operator for a
   valid feature name. Do nothing else.
2. Read `${CLAUDE_PLUGIN_ROOT}/references/steps/design.md` and follow it
   exactly, with `$ARGUMENTS` as its input. That file is the source of truth
   for this step; this wrapper adds nothing to it.
