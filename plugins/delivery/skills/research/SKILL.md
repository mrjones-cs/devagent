---
name: research
description: Verifies a feature's load-bearing design assumptions - public-facts register first, then web-search leads confirmed only on allowlisted official pages - and writes 03-research.md with the engine and every query sent, applying corrections to 02.
disable-model-invocation: true
argument-hint: <feature>
---

# delivery:research

Arguments: `$ARGUMENTS`

1. Take the first word of the arguments as the feature name. If it is missing
   or does not match `^[a-z0-9][a-z0-9-]*$`, stop and ask the operator for a
   valid feature name. Do nothing else.
2. Read `${CLAUDE_PLUGIN_ROOT}/references/steps/research.md` and follow it
   exactly, with `$ARGUMENTS` as its input. That file is the source of truth
   for this step; this wrapper adds nothing to it.
