---
format: delivery-plan/1
feature: sample-feature
generator: delivery@v0.1.0
step: 03-research
status: draft
date: 2026-10-14
reads: 01-requirements.md, 02-design.md
---

# Research: Sample feature

<!-- One paragraph: what was checked, with which engine, and anything that could not be checked. -->
Sample text for research summary

## Assumptions
<!-- One row per design assumption. Status: ✅ confirmed, 🔄 changed, ⛔ no longer true, ✨ new, ❓ unverified.
     Official source: one or more https:// URLs joined by " · ", or "live: <command>". 🔄 and ⛔ need an official-domain URL.
     Engine: web-search, official-page or manual. -->

| # | Assumption | Status | Current truth | Official source | Checked | Engine |
|---|---|---|---|---|---|---|
| A-1 | Sample text for assumption | ✅ | Sample text for current truth | https://docs.python.org/3/ | 2026-10-14 | manual |

## Changes nobody asked about (bounded look)
<!-- Things found nearby that the design did not ask about but should know: deprecations, new limits, better options. Keep it bounded. -->

| # | Finding | Status | Current truth | Official source | Checked | Engine |
|---|---|---|---|---|---|---|
| X-1 | Sample text for finding | ✅ | Sample text for current truth | https://docs.python.org/3/ | 2026-10-14 | manual |

## Queries sent
<!-- Every query sent to an outside search service, verbatim, one per line. Nothing client-identifying. -->
- python unittest discovery options

## Design changes recommended
<!-- What should change in 02 because of the above, citing A-nn or X-nn. The design step applies them to its change log. -->
- Sample text for recommended change
