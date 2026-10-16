---
format: delivery-plan/1
feature: {{feature}}
generator: delivery@{{release_tag}}
step: 04-review
status: draft
date: {{YYYY-MM-DD}}
reads: 01-requirements.md, 02-design.md, 03-research.md
classification: {{classification}}
---

# Review: {{feature_title}}

## Summary
<!-- Which lenses reviewed, counts by severity, and the findings that most change the design. -->
{{review_summary}}

## Findings
<!-- One block per finding. Heading: R-nn, severity (critical, high, medium, low), k/n lenses that raised it, lens names.
     Outcome is exactly one of: "applied → C-nn", "rejected — <reason>", "accepted risk — owner <role>, <rationale>", "needs-decision — D-n". -->

### R-01 · {{severity}} · 1/{{lens_count}} ({{lens_names}})
- section: {{design_section}}
- finding: {{finding}}
- fix: {{proposed_fix}}
- outcome: {{outcome}}
