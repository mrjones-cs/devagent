---
format: delivery-plan/1
feature: {{feature}}
generator: delivery@{{release_tag}}
step: 03-research
status: draft
date: {{YYYY-MM-DD}}
reads: 01-requirements.md, 02-design.md
---

# Research: {{feature_title}}

<!-- One paragraph: what was checked, with which engine, and anything that could not be checked. -->
{{research_summary}}

## Assumptions
<!-- One row per design assumption. Status: ✅ confirmed, 🔄 changed, ⛔ no longer true, ✨ new, ❓ unverified.
     Official source: one or more https:// URLs joined by " · ", or "live: <command>". 🔄 and ⛔ need an official-domain URL.
     Engine: web-search, official-page or manual. -->

| # | Assumption | Status | Current truth | Official source | Checked | Engine |
|---|---|---|---|---|---|---|
| A-1 | {{assumption}} | {{status_symbol}} | {{current_truth}} | {{official_url}} | {{YYYY-MM-DD}} | {{engine}} |

## Changes nobody asked about (bounded look)
<!-- Things found nearby that the design did not ask about but should know: deprecations, new limits, better options. Keep it bounded. -->

| # | Finding | Status | Current truth | Official source | Checked | Engine |
|---|---|---|---|---|---|---|
| X-1 | {{finding}} | {{status_symbol}} | {{current_truth}} | {{official_url}} | {{YYYY-MM-DD}} | {{engine}} |

## Queries sent
<!-- Every query sent to an outside search service, verbatim, one per line. Nothing client-identifying. -->
- {{query}}

## Design changes recommended
<!-- What should change in 02 because of the above, citing A-nn or X-nn. The design step applies them to its change log. -->
- {{recommended_change}}
