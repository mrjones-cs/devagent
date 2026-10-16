---
name: stack-selection
description: Standard for choosing a language and runtime version. Use at the start of a greenfield project, when proposing a stack, when adding a second language or runtime to a delivery, when picking a base image or managed service version, when setting up the project check command and type checking, or when a runtime is near end-of-life. Covers both the language-fit hierarchy and the newest-LTS rule.
---

# Stack Selection - Language Fit and Runtime Versions

Two rules that fire at the same moment: which language, and which version
of it. Both are tiebreakers that rank BELOW every real constraint.

---

# Part 1: Language Selection - Agentic Delivery Fit

When the language is genuinely ours to choose, pick the one the agent
loop converges fastest in. Fixed-bid margin depends on AI-assisted
throughput, and throughput is dominated by how quickly the toolchain
proves the code wrong — not by how good the first draft is. This is a
tiebreaker, not a stack opinion.

## The Hierarchy - work top down, stop at the first that binds

1. **Client constraint** — their platform, runtime, build system, or
   contract. When the client dictates the language, that ends it. Price
   in more iteration headroom if it is a weaker agentic fit; do not
   argue the stack.
2. **Existing codebase** — match what the repo already uses (see
   "Match the existing project" in Part 2). Never rewrite a working
   component into another language for agent convenience.
3. **Layer** — a browser UI is TypeScript; infrastructure is the IaC
   tool's language. These are not open questions.
4. **Workload** — data, ML, ETL, scientific and glue work is Python
   regardless of anything below. Services, CLIs, concurrent I/O and
   long-running daemons favour Go.
5. **Agent convergence** — only now does the default order apply.

## The Default Order (greenfield, nothing above binding)

**Go → Python → TypeScript → Java.**

- **Go** — fast compile, structural interfaces, explicit error returns.
  Simple enough that the model rarely misreads the type system, and the
  compiler is a cheap, precise oracle. Best net fit.
- **Python** — strongest first drafts and the deepest library ecosystem,
  but no compile-time oracle. Only ranks this high WITH strict typing
  and fast tests wired in (below).
- **TypeScript** — strong, and mandatory on the front end. Complex
  conditional types and heavy generic libraries are where it degrades.
- **Java** — capable, verbose, token-expensive. Framework magic
  (Spring, annotations, DI) is where the agent loses the thread.

**Prefer a rigorously typed language when correctness dominates cost.**
Rust and similar trade a weaker first draft for a strict oracle that
converges to higher final quality at higher token cost — justify it on
the requirement, not on taste.

## Make the Oracle Real - required, not optional

The ranking above holds only if the feedback loop actually exists. On
every project, whatever the language:

- **One check command that runs in under ~10 seconds.**
  `go build ./...`, `cargo check`, `tsc --noEmit`, `pytest -x -q` on a
  focused path. If the loop takes minutes, the agent idles on our
  margin. Record the command in the project's CLAUDE.md.
- **Strict type checking from day one** — `mypy --strict`, `tsconfig`
  strict, no `any`. Types are the cheapest oracle available.
- **TypeScript: run `tsc --noEmit` as a pre-commit GATE, not inside the
  edit loop.** Type errors surfaced mid-loop make the agent churn
  context on errors it cannot cleanly attribute. Get it running, then
  gate.
- **Dynamically typed languages lean on the test suite as the oracle** —
  the >= 80% line AND branch bar in TESTING STANDARDS (resident in
  CLAUDE.md) is doing double duty there and is not negotiable downward.

## Boundaries

- **Never surfaces in client-facing material.** "We build in X because
  our tooling likes it" is a worse answer in a proposal than "we build
  in what your platform runs." This informs the estimate, never the
  pitch.
- **No fixed-fee quote on a language with no working oracle** (COBOL,
  RPG, ABAP and similar). Reading legacy source to specify a replacement
  is in scope; writing it under a fixed bid is not. In anything the
  client sees, say "modernization" and "legacy systems" — never name
  the language.
- **This is not a licence to add a runtime.** A second language in a
  delivery means a second toolchain, a second LTS track, and a second
  thing the customer inherits. Justify it.
- **State the choice and the reason** when proposing a stack, alongside
  the version and EOL date Part 2 requires.

---

# Part 2: Runtime Versions - Newest LTS by Default

Build on the NEWEST long-term-support release of every runtime — not
merely one that is still supported. Customers inherit what we ship;
starting a new build on an LTS that is already half-consumed hands them
a migration years sooner than necessary.

## The Rule

**Latest LTS, not just any LTS.** When several LTS releases are still in
support, pick the most recent one. Do not default to the version you
know best, the one in your training data, or the one most tutorials use.

- Java: newest LTS (the 17 → 21 → 25 → … track), not an older LTS
  still receiving updates.
- Python: newest release with a full support window ahead of it — not
  the oldest 3.x still getting security fixes.
- Node: newest even-numbered release that has entered Active LTS.
- .NET: newest LTS (even-numbered), not the prior one.
- Ubuntu/Debian base images: newest LTS release.
- Managed services (RDS, Cloud SQL, Azure SQL, EKS/GKE/AKS): newest
  version on the standard-support tier — never one on paid extended
  support, which is a signal you are already behind.

**Verify before choosing.** Version numbers above are illustrative and
go stale. Check the current LTS and its EOL date against
endoflife.date or the vendor's support matrix at the time of the work.
State the version and its EOL date when proposing a stack.

## Boundaries

- **Not the bleeding edge**: LTS status is the gate. Never pick a
  release candidate, beta, nightly, or a non-LTS current release for
  anything a customer will run. A new major is adopted when it reaches
  LTS, not on release day.
- **Newly-minted LTS is fine**: Once a release is designated LTS, it
  qualifies immediately — no waiting for a `.1` or for the ecosystem to
  "settle." If a critical dependency does not yet support it, that is a
  dependency problem to surface, not a reason to silently drop back.
- **Not EOL either**: Flag any runtime inside 6 months of end-of-life or
  end-of-security-support and propose the upgrade path.
- **Match the existing project**: If a repo already targets a specific
  version, follow it — do not silently bump a runtime as a side effect
  of unrelated work. If it is behind the newest LTS, say so and propose
  the upgrade as its own piece of work.
- **Pin it**: Record the chosen version explicitly (`.nvmrc`,
  `.python-version`, `engines`, `pyproject.toml`, Dockerfile tag, IaC
  version argument). Never depend on `latest`, `:latest` image tags, or
  whatever the build agent happens to have installed.

## Exceptions

- **An older LTS is allowed when a hard dependency blocks the newest**
  (a library, driver, or vendor runtime with no compatible build) —
  name the blocker explicitly. "Less familiar" and "less common online"
  are not blockers.
- **Non-LTS is allowed when a required capability only exists there** —
  state the reason, the EOL date, and the migration plan for when the
  version goes unsupported.
- **Throwaway prototypes and internal experiments** may use current
  releases freely; mark them so they are never promoted to a deliverable
  without a version review.
- If the customer or an existing contract specifies a version, that
  governs — surface the risk if it is EOL, but follow it.

## Related

- LICENSE COMPLIANCE (resident in CLAUDE.md) — permissive licenses only
  in deliverables; check before adding a dependency
- `cloud-infra` — base images and managed service versions in IaC
- `observability` — naming the patching owner before handover
