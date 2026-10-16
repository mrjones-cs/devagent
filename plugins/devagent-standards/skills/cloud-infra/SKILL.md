---
name: cloud-infra
description: Standard for public cloud work. Use when provisioning, modifying, deploying, or reviewing cloud infrastructure on AWS/GCP/Azure/Cloudflare - Terraform/OpenTofu/Pulumi/CloudFormation/CDK/Bicep, accounts and OUs, IAM, VPCs, budgets and cost estimates, teardown scripts, or deploying a demo or client-facing surface. Covers IaC discipline, cost discipline, per-engagement account isolation, and the client-branding ban on deployed surfaces.
---

# Public Cloud - IaC, Cost, Isolation and Branding

Four rules that all fire the moment work touches a public cloud.

---

## Part 1: Infrastructure as Code Required

Infrastructure on a public cloud (AWS, GCP, Azure, Cloudflare) is defined
in code, always. A resource that exists but is not in the source is a
resource nobody can reproduce, review, or hand over.

- **Define every resource in code** — Terraform/OpenTofu, Pulumi,
  CloudFormation, CDK, Bicep. Follow the project's existing tool if one is
  present; default to Terraform on a new project.
- **No console clicks, no raw CLI provisioning.** `aws ec2 run-instances`
  and `gcloud compute instances create` are acceptable only for read-only
  inspection, or for a debugging resource torn down in the same session.
  Anything that outlives the session is IaC.
- **Change managed resources in the source, never in place.** Mutating a
  managed resource directly creates drift that surfaces later as a
  destroy-and-recreate in someone else's plan.
- **Remote state, with locking** (S3+DynamoDB, GCS, Terraform Cloud).
  Never commit state files — they contain resource detail and often
  secrets. State is also the thing a client cannot operate without, so
  see `engagement-closeout` before it becomes their problem.
- **Plan before apply, every time.** Review the plan, and show it to the
  user for anything destructive or cost-incurring. The plan is the only
  point at which a mistake is still free.
- **Secure defaults belong in the IaC**, not in a follow-up pass:
  least-privilege IAM, no public buckets by default, security groups
  scoped to the ports and CIDRs actually needed, encryption on, and no
  secret in a plaintext variable (use a secret manager or an SSM/Key Vault
  reference).
- **Run the IaC scanners as part of verification** — `tflint`, `checkov`,
  `tfsec`/`trivy config` — before reporting completion, not after.

**Exception**: when the user explicitly asks for a console change, comply,
then state the drift risk and offer to codify it.

---

## Part 2: Cost Discipline

Minimize cloud spend as a standing design goal. Solutions we build must
be cheap to run — for us and for the customers who inherit them; low
run-cost is part of delivery quality.

- **Right-size by default.** The smallest instance or tier that meets the
  requirement; scale up on evidence, not anticipation. No GPU or
  high-memory SKU unless the workload actually demands it.
- **Zero idle footprint.** Demo and POC infrastructure is torn down when
  not in use, and ships with a teardown script beside the deploy script.
  Prefer serverless and scale-to-zero; anything that must run 24/7 is
  justified explicitly.
- **Budget alarms on every account, in the baseline** — not added after
  the first surprise invoice.
- **Estimate before provisioning.** State the rough monthly cost when
  presenting a plan, and flag anything always-on.
- **Spend caps on metered vendors** wherever the console offers them (API
  vendors, STT/TTS). It is the blast-radius cap for a leaked key and for
  runaway usage alike.
- **Customer deliverables are held to this too.** Architect for low
  run-cost — serverless-first, storage lifecycle policies, right-sized
  databases — and surface the expected run-cost during design, because the
  customer inherits the bill.

---

## Part 3: Client Engagement Isolation - Cloud Accounts

Cloud account boundaries are how CUSTOMER CONFIDENTIALITY (resident in
CLAUDE.md) is enforced technically rather than by convention. "Right repo
only" governs source; this governs the accounts that source runs in.

- **One account per engagement**: Each client engagement gets its own
  cloud account in a `Clients` OU — never a shared account, never a
  shared VPC, never "we'll separate it by tags/prefixes later." Logical
  separation inside one account is not isolation; it is one IAM mistake
  away from cross-client disclosure (OWASP #4, missing tenant isolation).
- **Prefer the client's own account for production**: When an engagement
  reaches production, deploy into the client's tenancy. Their data stays
  theirs, which matches what the MSA already says about deliverables
  becoming customer IP, and it removes us as a breach target for data we
  have no reason to hold. We keep a scoped cross-account role, nothing
  more.
- **NEVER run a workload in the management account**: The org-management
  account holds SCPs, billing, and the identity store. A workload there
  means any application compromise is an organization compromise. It
  hosts governance only — no applications, no databases, no user-facing
  services. This includes internal tools; "it's only ours" is not an
  exception.
- **Account-creation baseline** (all of it, at creation, in IaC — not
  retrofitted): budget alarm · SCP scoped to the services the engagement
  actually needs · CloudTrail to the central security account · no IAM
  users, access via the identity provider only.
- **Teardown is a deliverable**: Every engagement account ships with a
  teardown script. Account deletion is the complete, demonstrable answer
  to a contractual "destroy our data at termination" obligation — keep it
  true so it can be relied on.
- **Cross-engagement access is per-person and per-account**: Access is
  granted to the accounts an individual's current engagement requires and
  no others. Blanket admin across all accounts is a finding, not a
  convenience — one phished credential should never reach two clients.
- **Multi-tenant internal platforms are the hard case**: An internal tool
  that legitimately holds several clients' material (a delivery platform,
  a shared pipeline) cannot get isolation from account boundaries, so it
  must earn it: enforced MFA, per-project data partitioning, and its own
  account away from both governance and any single client's workload.
  Treat it as the highest-value target we operate, because it is.

---

## Part 4: Deployed Surfaces Carry Our Branding Only

Anything we deploy to a public cloud must never identify a client.
Rationale: liability reduction — if our cloud footprint is breached or
discovered, it must not reveal who we are building for or what they are
building. This is the deployed-surface arm of CUSTOMER CONFIDENTIALITY.

- **Our branding only**: Deployed UIs and artifacts carry our own (or
  neutral/generic) branding — never a client's company name, logo, or
  signature trademark colors/branding.
- **Every deployed surface counts**: UI strings, logos, images, CSS
  brand colors, page titles and metadata, error pages, API responses,
  banner/demo-data labels, documents served by the app, domains, and
  cloud resource names (projects, services, buckets, artifact repos,
  tags, labels, secrets).
- **Client-specific demos included**: A demo built FOR a client still
  deploys with our branding. The client connection is made verbally or
  in non-deployed materials, never baked into the hosted artifact.
- **Verify at deploy time**: Before shipping, scan the served surface
  for client names and branding using the method in `public-release`,
  which covers what a name grep misses — bundles, source maps,
  metadata and exposed files. A hit is a ship blocker. Every client
  name is constrained by default — the rule, and its one narrow
  exception, are in the resident CONTENT CONSTRAINTS section of
  CLAUDE.md.
- **Scope boundary**: This governs what is DEPLOYED. Local repos,
  specs, decks, and docs remain governed by CUSTOMER CONFIDENTIALITY
  and the resident content constraints.

## Related

- OWASP Top 10 checklist: `${CLAUDE_PLUGIN_ROOT}/references/owasp-top10.md` (categories 4, 5)
- `encryption` — per-resource encryption verification and CMK choice
- `observability` — budget alarms as telemetry, runbook, teardown
- `stack-selection` — base image and managed service versions
- `public-release` — the leak scan for anything deployed publicly
