---
name: spec-panel
description: Reviews a feature's 02-design.md through independent lenses, one fresh reviewer per lens in parallel, at most five findings each; merges and dedupes them, routes decisions to the operator, applies fixes to 02, and writes 04-review.md.
disable-model-invocation: true
argument-hint: <feature>
---

# delivery:spec-panel

Arguments: `$ARGUMENTS`

1. Take the first word of the arguments as the feature name. If it is missing
   or does not match `^[a-z0-9][a-z0-9-]*$`, stop and ask the operator for a
   valid feature name. Do nothing else.
2. Read `${CLAUDE_PLUGIN_ROOT}/references/steps/spec-panel.md` and follow it
   exactly, with `$ARGUMENTS` as its input. That file is the source of truth
   for this step; this wrapper adds nothing to it.
