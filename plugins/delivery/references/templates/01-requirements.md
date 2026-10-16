---
format: delivery-plan/1
feature: {{feature}}
generator: delivery@{{release_tag}}
step: 01-requirements
status: draft
date: {{YYYY-MM-DD}}
tier: {{tier}}
ai_use: {{ai_use}}
---

# Requirements: {{feature_title}}

## Goal
<!-- One paragraph: the outcome the customer wants and why now. No solution detail. -->
{{goal}}

## Users and context
<!-- Who uses it, where it runs, what it connects to, and the constraints they bring. -->
{{users_and_context}}

## Functional requirements
<!-- Numbered, testable statements of what the system must do. One behaviour each. -->
1. {{functional_requirement}}

## Non-functional requirements
<!-- Security, performance, availability, accessibility, compliance, data handling, cost ceiling. Give numbers. -->
- {{non_functional_requirement}}

## Acceptance criteria
<!-- How the customer will decide it is done. Each criterion observable without reading the code. -->
- {{acceptance_criterion}}

## Out of scope
<!-- What was discussed and deliberately excluded, so nobody assumes it. -->
- {{out_of_scope_item}}

## Revisions
<!-- Dated list of changes to this file after approval, with who asked. -->
- {{YYYY-MM-DD}}: {{revision}}
