---
name: incident-breach
description: Playbook for a suspected breach of a customer-facing system - unauthorized access, data exposure, compromised account or key with blast radius, ransomware, or any event that may trigger a contractual notification clock. Use when a breach is suspected or confirmed, when assessing notification obligations under an MSA or DPA, or when preserving evidence before remediation. Leaked-credential response stays resident in CLAUDE.md; use that first if the finding is a secret in the wrong place.
---

# Suspected Breach of a Customer-Facing System

> If what you found is a live credential in source, git history, logs,
> scrollback or a document, that is the **resident** INCIDENT RESPONSE
> procedure in CLAUDE.md (flag → rotate → purge → record). Start there.
> This skill is for a suspected breach of a running system.

The notification deadline is **contractual**, and it starts before anyone
knows what happened. Enterprise MSAs and data processing agreements
routinely require notice within 24, 48 or 72 hours of *becoming aware* —
not of finishing the investigation. Missing that clock is a separate
breach from the incident itself, and it is the one the customer's lawyers
can prove.

## The procedure, in order

1. **Read the contract first, not last.** The engagement's MSA or DPA
   sets the clock, who must be told, and in what form. Find it before
   drafting anything. Where we are a subcontractor our clock is shorter
   than the prime's, because they need time inside theirs to meet the
   customer's.

2. **Preserve before you remediate.** Snapshot logs, images and state
   before rebuilding anything. This cuts against both the instinct to fix
   it and any routine cleanup rule — evidence destroyed during
   remediation does not come back, and its absence is read against us.

3. **One named person communicates.** No engineer notifies a customer
   directly. Facts only, no speculation about cause or scope — an early
   wrong number is the number everyone remembers.

4. **Notify the insurer early.** The Tech E&O / Cyber policy carries its
   own notice conditions, and remediation spending can become a coverage
   question if it happens before they are told.

5. **Log the timeline in the project's audit log** — discovery time and
   each notification. That timeline is the evidence the clock was met.

## Design for the clock at build time

A system that cannot answer "whose data, which records, over what window"
within a day cannot meet a 72-hour obligation. That is a logging and
data-model requirement during the build, not an incident-time scramble.
See the `observability` skill.

## What preservation cuts against

Two standing habits must yield here, deliberately:

- **The instinct to fix it.** Restoring service is not the first step;
  capturing state is.
- **Any routine cleanup or workspace-hygiene practice.** Do not delete
  temporary files, logs, or scratch state during an incident. (It is also
  why a standing "delete temporary files at session end" rule is a bad
  idea: it destroys exactly the evidence an incident needs.)

## Related

- INCIDENT RESPONSE / leaked credentials (resident in CLAUDE.md)
- `observability` — the logging that makes the clock answerable
- `cloud-infra` — account teardown as a data-destruction answer
- CUSTOMER CONFIDENTIALITY (resident in CLAUDE.md)
