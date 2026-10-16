---
name: document-artifact
description: Standard for generated document artifacts. Use whenever creating or regenerating a PDF, DOCX, PPTX, slide deck, one-pager, capability statement, brochure, white paper, case study, proposal, or an image rendered from one - by any method (python-pptx, reportlab, fpdf2, python-docx, Markdown-to-PDF, headless-browser export, templates, manual authoring). Covers the required copyright notice and the required page numbers, and points at the resident client-brand constraints.
---

# Document Artifacts - Copyright Notice and Page Numbers

Two required steps of document generation, not optional polish passes.
Both apply regardless of generation method and regardless of
"draft"/"template"/"illustrative" labeling. If it can leave the building,
it carries them.

> 🔴 **Before generating any artifact, re-read the resident CONTENT
> CONSTRAINTS section in CLAUDE.md.** No client name may appear in an
> exported artifact — not in slide titles, footers, chart labels,
> narrative text, embedded images, metadata, or filenames. This is a
> blanket rule with no list to consult; the only exception is explicit
> authorization for a specific name in a specific artifact. Any list of
> names is deliberately kept out of this skill and out of any shared
> repo. Use generic language ("our company", "the bank", "the firm"),
> bracketed placeholders (`[COMPANY]`, `[CLIENT]`), or leave the field
> blank for manual insertion after delivery. When unsure whether a string
> qualifies, default to generic language.

---

## Part 1: Copyright Notice

All marketing material created for our own company carries a copyright
notice. Content is copyrighted automatically on creation; the notice
defeats "innocent infringement" defenses, signals ownership, and meets
enterprise/government buyer expectations.

### Notice Format

> © <year> <legal name>. All rights reserved.

- `<legal name>` is the organisation's full legal name from the
  ORGANISATION section of the resident CLAUDE.md (for example "Example
  Software LLC") — never a short or trading name. If that section still
  reads `[LEGAL NAME]`, ask rather than guess.
- Year = current year at time of creation. When updating an existing
  artifact whose original publication year is known, use a range
  (e.g., © 2026–2027 Example Software LLC. All rights reserved.).

### Where It Goes

- **Slide decks (.pptx / PDF decks)**: footer of each slide, or at
  minimum the title and closing slides.
- **Documents (PDF, DOCX)**: footer of each page, or the closing/back
  page — capability statements, one-pagers, brochures, white papers,
  case studies.
- **Website pages**: site footer.

### DO NOT stamp the notice on

- **Customer deliverables**: Delivered code, docs, and artifacts become
  the customer's IP. Never place our copyright notice on engagement
  deliverables unless the MSA explicitly provides otherwise.
- **Social posts** (LinkedIn posts/ads and similar in-platform content):
  no notice — platforms attribute and timestamp; a © line reads awkward
  and adds nothing.
- **Government submissions**: Proposals/RFP responses get the notice
  plus a proprietary-data legend where appropriate, but
  solicitation-prescribed legends (FAR restrictive markings) take
  precedence — follow the solicitation, don't blindly stamp the standard
  line.

### Note

The notice does not, by itself, unlock statutory damages or attorney's
fees — that requires registration with the US Copyright Office. Not
required for routine collateral; worth suggesting for flagship pieces
if enforcement ever becomes likely.

---

## Part 2: Page Numbers

Every PDF or Word document (.pdf, .docx) includes page numbers.

- **Format**: "Page X of Y" in the footer; plain "X" acceptable when
  the footer is crowded (e.g., shares space with a copyright notice).
- **Placement**: footer, centered or right-aligned — match the
  document's existing footer layout if one exists.
- **Exceptions**: single-page documents (one-pagers, certificates,
  cover letters that fit one page) and slide decks exported to PDF
  (slides use slide numbers per the deck template instead).
- **Regenerating an existing document**: if the source document lacks
  page numbers, add them as part of the rebuild.

### Known failure points

- **fpdf2 / reportlab total-page placeholders.** Getting "of Y" right
  needs either a two-pass render or the library's alias/deferred
  mechanism. A literal `{nb}` or a stale total shipping in the footer is
  the single most common defect here.
- **Headless-browser PDF export ignores CSS `@page` margin boxes.**
  Chrome's print-to-PDF will not render `@page { @bottom-center { content:
  counter(page) } }`. If page numbers are required, do not use headless
  Chrome — use a library with real footer control.
- **pandoc needs a PDF engine.** Without LaTeX (or weasyprint) installed,
  `pandoc -o out.pdf` fails or silently routes elsewhere. Check the
  engine exists before relying on it.

---

## Verification

**Invoke the `verification-methods` skill before reporting any artifact
done.** It owns verification for every work type, holds the
rendered-document recipe in full, and lists the engine traps that make
page numbers silently vanish. This skill defines what must be true; that
one defines how to prove it.

## Related

- `verification-methods` — how to prove both requirements above are met
- VERIFICATION (resident in CLAUDE.md) — render it and look at it
- CONTENT CONSTRAINTS (resident in CLAUDE.md) — the client-name ban
- CUSTOMER CONFIDENTIALITY (resident in CLAUDE.md) — naming a client
- `dataviz` (built-in skill) — charts inside these artifacts
- `public-release` — a document that will be published or posted to a URL
