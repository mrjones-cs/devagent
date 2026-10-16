---
name: verification-methods
description: Method for proving a built thing actually works before reporting it done. Use when finishing, validating, testing, or about to claim completion on ANY work product - code, a PDF/DOCX/PPTX or slide deck, a diagram or chart, a web page or UI change, a deployed endpoint, or cloud infrastructure. Covers finding the project's check command, what to run per artifact type, rendering and reading a visual artifact instead of the source that made it, probing a deployed surface, and how to report a partial or failed check honestly.
---

# Verification Methods - Proving It Works, Per Artifact Type

The rule is resident in CLAUDE.md and does not load on demand: **before
reporting anything complete, prove it works with an observation you made,
after the change, on the real artifact.** This skill is the *how* for each
kind of thing we build.

One idea underneath all of it: **verify the thing that ships, not the
thing that produced it.** Source code is not a rendered page. A generator
script is not a PDF. A Terraform file is not a bucket. Every recipe below
is a way of getting your eyes onto the artifact itself.

> A newer timestamp is not accuracy. A generated file can be newer than
> every input and still assert something false — this has happened here.
> Check the claims, not the mtime.

---

## Code

1. **Find the project's check command — never invent one.** Look in this
   order: the project's own CLAUDE.md · `Makefile` / `justfile` ·
   `package.json` scripts · `pyproject.toml` / `tox.ini` · the CI
   workflow. If none exists, say so and propose one rather than guessing
   a path. Every project should have one that runs in under ~10 seconds
   (see `stack-selection`); a missing one is a finding to raise.
2. **Run tests, the type checker, and the linter. Report the counts.**
   `24/24 passing, mypy clean, ruff clean` — numbers, not adjectives.
3. **Coverage on the lines you changed**, ≥80% line AND branch. Whole-repo
   coverage hides an untested new function completely.
4. **Prove the test actually covers the fix.** Revert the fix, or assert
   the old behaviour, and watch the test fail. A test that passes both
   with and without the change tests nothing. This is the single most
   common false green.
5. **A green suite that never executes the changed lines is not
   evidence** — say so explicitly rather than letting the tick imply
   coverage it does not have.
6. **Watch for wrong-runner flags.** `--testPathPattern` is Jest, not
   Vitest; a flag from the wrong runner fails in a way that reads exactly
   like a broken test.
7. **`git diff` every time** — unintended edits, removed code, stray
   debug output, files you did not mean to touch.

## Rendered documents - PDF, DOCX, PPTX, decks, one-pagers

`document-artifact` owns *what must be true* (the copyright notice, page
numbers). This is how you prove it.

- **Render it and read every page.** Never report a visual artifact done
  from the source that generated it. Read the actual pages — page count
  included, because content growth silently repaginates.
- **Page numbers on every page including the last, with a real total.** A
  literal `{nb}` or a stale total is the most common defect. reportlab and
  fpdf2 need a two-pass render or their alias mechanism for "of Y".
- **Confirm the copyright notice** appears where `document-artifact`
  requires it, with the full legal name.
- **Grep the extracted text for client names** — every client name is
  constrained by default; see CONTENT CONSTRAINTS, resident in CLAUDE.md,
  for the one narrow exception. A hit is a ship blocker,
  same weight as a failing test. Check metadata and the filename too.
- **Look for clipping and overflow**: text running off the page, a table
  column so narrow the header wraps mid-word ("Lines" → "Line s"), code
  blocks whose leading whitespace collapsed, an orphaned heading alone on
  a final near-empty page.
- **Known engine traps**: headless-browser PDF export ignores CSS `@page`
  margin boxes, so page numbers silently vanish — never use it when they
  are required. `pandoc -o out.pdf` needs a PDF engine installed.

## Diagrams and charts

Valid source that renders illegibly is not done. Syntax checking is not
verification here — **render to an image and look at it.**

- **Check what rendering breaks**: truncated or clipped labels,
  overlapping nodes and text, arrows connecting the wrong nodes or
  pointing the wrong way, a legend that no longer matches the series,
  missing axis labels or units, and text too small to read at the size it
  will actually be displayed.
- **Verify the numbers against the source data**, not merely that a chart
  drew. A chart plotting the wrong column looks perfect and is worse than
  no chart, because it will be believed.
- **Check colour against the real destination background**, at 4.5:1 for
  text and 3:1 for large text and UI components — and in both light and
  dark if it ships in both. See the `dataviz` skill and the resident
  ACCESSIBILITY section.
- **Re-render after every edit.** A cached SVG or PNG will happily show
  you the previous version and let you sign off on it.

## Deployed and UI surfaces

- **Probe unauthenticated first**, before anything else: real endpoints
  must return 401/403. Then a valid token for the wrong tenant → 403/404.
  Then an oversized and a malformed payload → rejected cleanly. See
  `api-security` and `auth-portal`.
- **`curl` ignores CORS entirely.** A restrictive CORS policy is not
  access control and proves nothing.
- **Check headers on the deployed response** with `curl -I`, never in the
  config file — CDNs, load balancers and frameworks add and strip headers
  in transit.
- **Load the real page and read the console.** CSP violations, mixed
  content and missing headers surface there and nowhere else.
- **Trace the actual request path.** A WAF or rate limiter that the
  request does not pass through is theatre with a monthly bill.
- **A public surface gets a leak scan of what was deployed**, not of its
  source — bundles, source maps, metadata, exposed files, and git history
  for a repo going public. See `public-release`.
- **New UI gets a keyboard pass** — tab order, visible focus on every
  interactive element — plus an automated axe/Lighthouse run.
- **Infrastructure**: `plan` before `apply`, then confirm the created
  resource's **actual** state (encryption on, access scoped, correct
  region) rather than the author's intent. Run the IaC scanners
  (`checkov`, `tfsec`/`trivy config`, `tflint`). See `cloud-infra` and
  `encryption`.

---

## Report what you actually ran

State the command and its result, including partial and negative ones:

- ✅ "Tests pass (24/24), ruff clean, 86% branch coverage on changed lines"
- ✅ "Rendered to PDF, read all 9 pages — page numbers correct, no clipping"
- ⚠️ "Returns 401 unauthenticated as expected; tenant-boundary case NOT
  tested — no second tenant exists in the dev environment"

**Never report done on a failing check. Never describe a check you did
not perform.** When something could not be verified, name which part and
why. An honest gap is useful; an assumed pass is a defect with a green
tick next to it.

If a check was skipped because it was slow, awkward, or seemed
unnecessary, that is still a gap and still gets stated.

## Related

- VERIFICATION (resident in CLAUDE.md) — the rule this skill implements
- TESTING STANDARDS and ACCESSIBILITY (resident in CLAUDE.md) — the bars
- `document-artifact` — what a document must carry
- `dataviz` — chart form, colour and legibility
- `stack-selection` — the one check command under ~10 seconds
- `api-security` · `auth-portal` — what to probe on a deployed surface
- `cloud-infra` · `encryption` — confirming real resource state
- `observability` — proving telemetry exists on the deployed surface
- `public-release` — the leak scan for anything going public
