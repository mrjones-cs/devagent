---
name: engagement-closeout
description: Standard for ending an engagement. Use when a project is finishing, delivering, or being handed over - final delivery and acceptance, transferring repos, IaC state, secrets and cloud accounts, revoking access in both directions, license and IP attestation or an SBOM at delivery, returning or destroying customer material and session artifacts, agreeing who owns and patches the system after handover, and closing the engagement out in the audit log. Also use when a contract's termination, data-return or data-destruction clause has to be satisfied.
---

# Engagement Close-Out - Walking Away Cleanly

Every other standard here governs building and running. This one governs
**stopping**, which is where obligations come due and where nobody is
watching any more. An engagement that is "finished" but not closed out
leaves live credentials, unowned patching, and undischarged contractual
duties — all of it invisible, because the work is done and the invoice is
paid.

Close-out is a deliverable with a date, not a wind-down that happens by
itself. `observability` covers making the system *operable* by its new
owner; this covers everything else about leaving.

---

## Start from the contract, not from the code

- **Read the MSA, SOW and any DPA before doing anything else.** They set
  what must be returned, what must be destroyed, on what deadline, what
  final acceptance requires, and what survives termination
  (confidentiality, IP assignment, warranty windows).
- **Data return and destruction are usually explicit obligations** with a
  clock. Find the clause and the deadline before touching anything, because
  destruction is irreversible and "return" may require a format.
- **Know what survives.** Confidentiality does not end with the
  engagement. Neither does CUSTOMER CONFIDENTIALITY (resident in
  CLAUDE.md) — a closed engagement's material stays confidential forever,
  and cross-contamination into the next project is still prohibited.

## Access revocation runs in BOTH directions

Most close-outs revoke the client's access to our systems and forget the
reverse, which is the dangerous half: **we keep standing access to a
customer environment nobody is monitoring on either side.**

- **Enumerate our access into their world**: cloud roles and cross-account
  trust, VPN, SSO/IdP guest accounts, repository collaborator rights, CI
  secrets, database users, dashboards, ticketing, Slack Connect, vendor
  consoles bought on their behalf.
- **Enumerate their access into ours**: shared repos, our cloud accounts,
  our CI, our Slack, any account we provisioned for them.
- **Revoke, then prove it.** Attempt the access after revoking and confirm
  it fails. An unused role is not a revoked role.
- **Rotate every shared or jointly-known secret** at close-out even if it
  was never exposed. Anyone who saw it during delivery still knows it.
- **Personal devices and local copies**: confirm cloned repos, downloaded
  exports and local databases are removed from our workstations.

## Transfer the things that outlive us

- **Repositories** with full history, plus write access moved to them and
  ours removed. Confirm no deliverable code lives only in a fork.
- **IaC state** is the highest-risk transfer: a Terraform state file left
  in our bucket means they cannot change their own infrastructure without
  us. Move state, re-point the backend, and prove `plan` runs clean on
  their side.
- **Secrets manager entries**, with the values rotated on arrival so we no
  longer hold anything live.
- **Cloud accounts**: either move the account into their organization or
  tear it down. Per `cloud-infra`, account deletion is the complete,
  demonstrable answer to a destruction obligation — do not leave an
  engagement account parked and paid for by us.
- **Domains, DNS and certificates**, with renewal ownership stated. An
  expiring certificate nobody owns is the most common post-handover
  outage.
- **Vendor accounts and billing** bought for the engagement: transfer or
  cancel, and confirm MFA is enabled on anything transferred (resident
  VENDOR ACCOUNTS).

## Attest the IP and the licensing

Delivered code becomes the customer's IP, so the licence position has to be
provable at the moment of delivery, not reconstructed later.

- **Produce a dependency and licence inventory (SBOM where the toolchain
  supports it)** for what actually ships, and state that it is permissive
  only, per LICENSE COMPLIANCE (resident in CLAUDE.md).
- **Flag any copyleft or unknown-provenance dependency explicitly** rather
  than letting delivery imply a clean bill.
- **No copyright notice of yours on customer deliverables** — see
  `document-artifact`. Check the artifacts actually shipped, not the
  templates.
- **Confirm no other client's material is present** in anything delivered:
  code, comments, fixtures, test data, diagrams, commit messages.

## Customer material and session artifacts

- **Session artifacts are a copy of customer material** (resident AGENT
  AND DEVELOPER TOOLCHAIN SECURITY): transcripts, `NOTES.md`, scratch
  files, exported logs, prompt logs, local databases and screenshots. They
  inherit the source's classification and they are exactly what a
  destruction clause covers.
- **Return or destroy per the contract**, then record which was done and
  when. "We think it was deleted" satisfies nothing.
- **Do not retain material for future reuse.** A future engagement may not
  read it, so keeping it creates obligation with no benefit.

## Name the owner of the gap

- **Who owns the system between handover and their team's readiness?** It
  is rarely zero days. Put the window, the owner and the escalation path in
  writing; unowned, it defaults to us for free.
- **Patching owner and cadence** must already be named per
  `observability`. Confirm it survived into the signed handover rather
  than living only in a runbook draft.
- **Support after close** is a priced arrangement or it is nothing. Under a
  fixed bid an informal "just ping me" is unbilled work we get called about
  anyway.

## Verify, do not assume

- **Prove revocation** by attempting each access path after removing it.
- **Prove the transfer** by having them run the thing on their side —
  `plan` against their state, a deploy from their CI, a login with their
  own credentials.
- **Re-probe the deployed surface** unauthenticated after any account move;
  boundaries change when accounts do (see `api-security`, `auth-portal`).
- **Log the close-out** in the project's audit log: what transferred, what
  was destroyed, what was revoked, and the dates. That record is the
  evidence a contractual obligation was met.
- Report what was actually confirmed versus assumed, per the resident
  VERIFICATION section.

## Related

- `observability` — operability, runbook, patching owner (the half that
  must exist before this one runs)
- `cloud-infra` — account teardown and per-engagement isolation
- `incident-breach` — preservation duties can outlive an engagement
- `document-artifact` — no notice of yours on customer deliverables
- LICENSE COMPLIANCE · CUSTOMER CONFIDENTIALITY · VENDOR ACCOUNTS ·
  AGENT AND DEVELOPER TOOLCHAIN SECURITY (all resident in CLAUDE.md)
