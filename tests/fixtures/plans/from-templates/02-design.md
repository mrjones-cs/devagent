---
format: delivery-plan/1
feature: sample-feature
generator: delivery@v0.1.0
step: 02-design
status: draft
date: 2026-10-14
reads: 01-requirements.md
tier: M
personal_data: false
calls_model: false
has_ui: false
flagged: false
---

# Design: Sample feature

## 1. Architecture
<!-- Components and how they connect. A rendered diagram (mermaid) plus a sentence per component. -->
Sample text for architecture

## 2. Data flow
<!-- Follow one request and one piece of data end to end, including where it is stored and who can read it. -->
Sample text for data flow

## 3. Stack
<!-- Language, runtime (newest LTS, pinned), frameworks, managed services, and why each. -->
Sample text for stack

## 4. Authentication and authorization
<!-- Who logs in, how (MFA), how sessions work, and how each object is authorized. Deny by default. -->
Sample text for auth

## 5. APIs
<!-- Each endpoint or interface: caller, auth, input bounds, rate limit, error behaviour. -->
Sample text for apis

## 6. Data classification
<!-- Each data store and field class: classification, encryption at rest and in transit, retention. -->
Sample text for data classification

## 7. Threat model
<!-- Assets, entry points, abuse cases, and the control for each. Name what is accepted and why. -->
Sample text for threat model

## 8. Observability
<!-- Logs with a correlation ID, health checks, alerts with owner and runbook, backups, RTO and RPO, patching owner. -->
Sample text for observability

## 9. Cost
<!-- Build and run cost with assumptions, budget alarm, and teardown plan. -->
Sample text for cost

## 10. Test strategy
<!-- What is tested at each level, the single check command, and the coverage target (80% line and branch on new code). -->
Sample text for test strategy

## 11. Assumptions to verify
<!-- Every fact the design leans on that could be wrong. Load-bearing means the design fails if it is false. -->

| # | Assumption | Load-bearing | Status |
|---|---|---|---|
| A-1 | Sample text for assumption | yes | ❓ |

## 12. Open decisions
<!-- Questions only the operator or customer can answer. Each gets a D-n; none may remain once step 05 exists. -->

| ID | Decision needed | Status |
|---|---|---|
| D-1 | Sample text for decision needed | needs-decision |

## Change log
<!-- One row per change after the first draft. Source is one of: operator, research A-nn, research X-nn, R-nn, render check, T-nn. -->

| ID | Date | Source | Section | Change |
|---|---|---|---|---|
| C-01 | 2026-10-14 | operator | section 1 | Sample text for change |
