---
name: public-release
description: Standard for anything about to become public. Use before publishing, launching or deploying a website, landing page, blog post, case study, portfolio or marketing page; before making a repository public, open-sourcing code, posting a gist, or sharing a screenshot, recording or demo outside the firm; and when uploading a document to a public URL. Covers client identifiability beyond names, content provenance, hidden channels in the built output (bundles, source maps, metadata, EXIF, exposed files, git history), and what a hit means.
---

# Public Release - Nothing Goes Public Unreviewed

Publication is the one disclosure that cannot be recalled. A page that was
live for an hour has been crawled, cached and archived; a repository that
was public for a minute has been cloned by secret-scanning bots. Everything
below runs **before** the release, because afterwards it is incident
response.

The asset at risk is the one CUSTOMER CONFIDENTIALITY (resident in
CLAUDE.md) protects: knowledge of what a client is building. A name grep
is necessary and nowhere near sufficient — most leaks name nobody.

---

## What counts as public

- Websites, landing pages, blog posts, case studies, portfolio and
  marketing pages — **including our own**, which carry no client branding
  and so slip past `cloud-infra` Part 4 entirely.
- A repository made public, open-sourced code, a gist, a public package.
- Screenshots, screen recordings, conference talks and demos shown outside
  the firm.
- A document uploaded to any URL reachable without a login. "Unlisted",
  "unlinked" and "obscure path" are public.
- A staging or preview deployment with no authentication in front of it.

## 1. Identifiability, not just names

Ask of every sentence, image and caption: **could a reader work out who
the client is, or what they are building?** If yes, treat it exactly as a
client name — CONTENT CONSTRAINTS (resident in CLAUDE.md) applies, and its
ask-for-authorization clause is the only way through.

- **Combinations identify.** Industry + scale + geography + timeline
  ("a top-10 US bank's 2026 real-time payments rebuild") names a client as
  surely as the name does. So do distinctive product features, launch
  dates, headcounts and dollar figures.
- **Visual identity identifies.** Brand colours, logo shapes, UI layouts
  and product screenshots — even cropped, even blurred.
- **Testimonials and quotes** carry a person's title and employer.
  Attribution needs the same explicit authorization as a name.
- **Generalise until it could be anyone**, or ask. Never resolve the
  doubt silently in favour of publishing.

## 2. Content provenance

Every diagram, code snippet, screenshot, dataset and sample record must
trace to material your organisation owns or created generically for the
purpose.

- **Nothing lifted from an engagement** — a client repo, spec,
  architecture deck, ticket or meeting note — even redacted, even
  "illustrative". This is the no-cross-contamination rule applied to
  publication.
- **Redraw, do not redact.** A redacted client diagram keeps its shape,
  and the shape is the design.
- **Demo data is synthetic.** Never a client's records, schema or field
  names.
- **Licences**: third-party images, fonts and code on the page follow
  LICENSE COMPLIANCE (resident in CLAUDE.md).

## 3. Scan what was built, not its source

The source can be clean while the build leaks. Inspect the deployed
surface, or the exact artifact that will be uploaded.

- **Bundles and source maps.** Fetch the shipped JS and CSS. Production
  must not serve `.map` files; grep bundles for internal hostnames,
  absolute file paths, usernames, API endpoints, feature flags and
  commented-out client strings.
- **Markup the browser hides**: HTML comments, `<meta>` and Open Graph
  tags, `alt` and `title` text, `data-*` attributes, hidden form fields,
  JSON-LD, inline config objects.
- **Files that should not be there.** Probe the live site for a `.git`
  directory, `.env`, `.DS_Store`, backup files, `*.map`, CMS export
  folders and directory listings. A 200 on any of them is a hit.
- **Crawl maps.** `sitemap.xml` and `robots.txt` advertise paths;
  `robots.txt` lists exactly the paths someone wanted hidden.
- **Embedded metadata.** Strip EXIF and GPS from images. Check downloadable
  PDF, DOCX and PPTX properties — author, company, title, revision history,
  tracked changes, speaker notes, hidden slides.
- **Screenshots and recordings**: read every pixel, not the subject —
  browser tabs, bookmarks bar, notifications, terminal history, file
  trees, window titles, the second monitor.
- **Every client name, everywhere above.** Grep the full fetched surface
  and the extracted document text. Every client name is constrained by
  default.

## 4. A repository going public

- **Scan the whole history, not the working tree.** A file deleted three
  years ago is still in every clone. Search all commits, all branches and
  all tags for secrets and for client strings.
- **Commit metadata is content.** Author names, emails, branch names and
  commit messages ship with the repo.
- **Issues, PRs, wikis, releases and Actions logs** become public with it.
- When history cannot be made clean, publish a fresh repository from a
  reviewed snapshot instead of flipping visibility.

## 5. A hit blocks the release

- **Any hit is a ship blocker**, same weight as a failing test. Fix it and
  re-scan the rebuilt output; do not fix the source and assume.
- **A live secret is an incident, not a hit** — follow INCIDENT RESPONSE
  (resident in CLAUDE.md): flag, rotate, purge, record. If it was already
  public, rotate first.
- **Already published?** Take it down, then treat it as possible exposure
  of customer material: invoke `incident-breach`. Caches, archives and
  search indexes need removal requests too.

## Verify

Report what you scanned and how, per the resident VERIFICATION section —
which surface, which files fetched, which history range searched. "Looked
fine" is not a scan. Name anything you could not check (a CMS draft you
cannot see, a CDN cache you cannot purge).

## Related

- `cloud-infra` Part 4 — client branding on deployed cloud surfaces
- `document-artifact` — documents that will be published
- `verification-methods` — deployed and UI surfaces
- `web-browser-security` — attacks *on* a page; this covers what a page
  discloses
- `incident-breach` — when something confidential was already published
- CUSTOMER CONFIDENTIALITY · CONTENT CONSTRAINTS · LICENSE COMPLIANCE ·
  INCIDENT RESPONSE (all resident in CLAUDE.md)
