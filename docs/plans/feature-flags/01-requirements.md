---
format: delivery-plan/1
feature: feature-flags
generator: delivery@1.0.1
step: 01-requirements
status: draft
date: 2026-10-17
tier: M
ai_use: none - the feature calls no model and gives no agent new tools
---

# Requirements: Feature flags

## Goal
Let a DevAgent delivery put a feature behind a flag, for two outcomes the
operator asked for together. First, each verified task can land on the main
branch while the unfinished feature stays switched off, which makes short-lived
branches and trunk-based integration safe for agent-built work. Second, the
system delivered to the client can be rolled out gradually and switched off
fast. Flags must not pile up: every flag is planned to be removed.

## Users and context
- Operators: people running the DevAgent delivery workflow to build client
  software in Claude Code.
- Clients: they inherit the delivered system and every flag still live in it.
- Context: DevAgent is two Claude Code plugins (`devagent-standards`,
  `delivery`) plus resident rules. This feature adds a standards skill and
  changes the delivery steps, templates and plan checker. The flags themselves
  live in the client's code, not in DevAgent.
- Flagging is opt-in per plan: the design decides whether a feature is
  flagged, and nothing changes for plans that are not.

## Data handled
- Personal data, regulated data, credentials, production data: none. DevAgent's
  own code handles plan files only.
- Client IP: a flagged plan names a client's unreleased feature and its
  rollout. It lives in the engagement's own `docs/plans/` and is confidential
  like any plan.

## Client constraints
DevAgent itself is the product here.
- MIT licence. Standard-library Python and bash only; no new dependency
  (CONTRIBUTING.md).
- Claude Code plugin format, at the version pinned in `plugins/delivery/PINS.md`.
- CI: GitHub Actions, every suite on every push.
- SSO / IdP, cloud and region, approved-vendor list, compliance regime,
  contract clauses on residency, retention and breach notice: none apply.
- No flag vendor default, and no flag runtime shipped (see Out of scope).
- AI-use position: the feature calls no model, retrieves no documents for a
  model, and gives no agent new tools. The new skill is text the agent reads,
  so the resident rules on untrusted file content still apply.

## Functional requirements
1. A plan can declare a feature as flagged; a plan that does not is unchanged.
2. For a flagged feature, the plan includes a task that adds the flag, off by
   default, before any task that depends on it.
3. For a flagged feature, the plan includes a task that removes the flag and
   the code path it guarded, with a named owner and a removal date.
4. Every task between those two is verified with the flag on and with it off.
5. The plan checker rejects a flagged plan that has no removal task, or whose
   removal task has no owner or no date, and names the rule.
6. `save` reports every flag past its removal date.
7. `save --handover` lists every flag still live in the deliverable, with its
   owner.
8. A `feature-flags` standards skill sets the standard for flags in client
   code: server-side evaluation for security-relevant flags, audited flag
   changes, a kill switch for features that call a model, flagged-off code
   still present in public bundles, hosted flag services handled as vendors,
   and gradual (percentage or cohort) rollout.

## Non-functional requirements
- No new dependency; checkers stay standard-library Python.
- Changed checker code meets the repository bar: at least 80% line and branch
  coverage, with a negative test for each new rule.
- The repository check commands keep running in seconds, as today.
- The new skill follows the existing standards' shape and passes
  `check-skills.py`, including its resident stub and every prose figure that
  counts skills.

## Acceptance criteria
- AC-1: A flagged plan whose flag-removal task has an owner and a date passes
  `check-plan.py`; removing the task, the owner or the date makes it fail,
  naming the rule.
- AC-2: Unflagged plans are unaffected: every existing fixture and the example
  plan pass unchanged.
- AC-3: `workflow` on a flagged design writes a 05 whose first task adds the
  flag (off by default) and whose last task removes it; every task in between
  is verified with the flag on and off.
- AC-4: `save` reports each flag past its removal date; `save --handover` lists
  every live flag with its owner.
- AC-5: A `feature-flags` standards skill installs, has a resident stub, passes
  `check-skills.py`, and covers server-side evaluation for security-relevant
  flags, audited changes, a kill switch for model-calling features, flagged-off
  code in public bundles, hosted flag services as vendors, and gradual
  rollout.
- AC-6: No new dependency, and every CI suite passes.

## Out of scope
- A flag library, service or SDK shipped by DevAgent: the client's code uses
  whatever its design picks.
- A default or recommended hosted flag vendor, or any integration with one.
- Feature flags in DevAgent's own scripts and hooks.
- Experiments and A/B tests. (Gradual rollout is in scope.)

## Revisions
- 2026-10-17: first draft from the brainstorm with the operator.
