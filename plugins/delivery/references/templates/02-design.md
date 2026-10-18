---
format: delivery-plan/1
feature: {{feature}}
generator: delivery@{{release_tag}}
step: 02-design
status: draft
date: {{YYYY-MM-DD}}
reads: 01-requirements.md
tier: {{tier}}
personal_data: {{true_or_false}}
calls_model: {{true_or_false}}
has_ui: {{true_or_false}}
flagged: {{true_or_false}}
---

# Design: {{feature_title}}

## 1. Architecture
<!-- Components and how they connect. A rendered diagram (mermaid) plus a sentence per component. -->
{{architecture}}

## 2. Data flow
<!-- Follow one request and one piece of data end to end, including where it is stored and who can read it. -->
{{data_flow}}

## 3. Stack
<!-- Language, runtime (newest LTS, pinned), frameworks, managed services, and why each. -->
{{stack}}

## 4. Authentication and authorization
<!-- Who logs in, how (MFA), how sessions work, and how each object is authorized. Deny by default. -->
{{auth}}

## 5. APIs
<!-- Each endpoint or interface: caller, auth, input bounds, rate limit, error behaviour. -->
{{apis}}

## 6. Data classification
<!-- Each data store and field class: classification, encryption at rest and in transit, retention. -->
{{data_classification}}

## 7. Threat model
<!-- Assets, entry points, abuse cases, and the control for each. Name what is accepted and why. -->
{{threat_model}}

## 8. Observability
<!-- Logs with a correlation ID, health checks, alerts with owner and runbook, backups, RTO and RPO, patching owner. -->
{{observability}}

## 9. Cost
<!-- Build and run cost with assumptions, budget alarm, and teardown plan. -->
{{cost}}

## 10. Test strategy
<!-- What is tested at each level, the single check command, and the coverage target (80% line and branch on new code). -->
{{test_strategy}}

## 11. Assumptions to verify
<!-- Every fact the design leans on that could be wrong. Load-bearing means the design fails if it is false. -->

| # | Assumption | Load-bearing | Status |
|---|---|---|---|
| A-1 | {{assumption}} | {{yes_or_no}} | ❓ |

## 12. Open decisions
<!-- Questions only the operator or customer can answer. Each gets a D-n; none may remain once step 05 exists. -->

| ID | Decision needed | Status |
|---|---|---|
| D-1 | {{decision_needed}} | needs-decision |

## Change log
<!-- One row per change after the first draft. Source is one of: operator, research A-nn, research X-nn, R-nn, render check, T-nn. -->

| ID | Date | Source | Section | Change |
|---|---|---|---|---|
| C-01 | {{YYYY-MM-DD}} | operator | {{section}} | {{change}} |
