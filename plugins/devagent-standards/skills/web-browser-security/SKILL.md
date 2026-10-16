---
name: web-browser-security
description: Standard for anything that renders in a browser. Use when building or reviewing a web page, SPA, or front end - Content Security Policy, security headers, XSS, CSRF, cookies, clickjacking, third-party scripts and analytics tags, file uploads, or rendering user-supplied or model-generated HTML/Markdown. Also use when adding a script tag, a chat widget, or a tag manager, and when hardening a deployed page.
---

# Web Application and Browser Security

The browser is a hostile execution environment we do not control, and it
is where a public portal is actually attacked. `auth-portal` and
`api-security` secure the server. This secures what runs on the user's
machine. A portal can satisfy every rule in both of those and still be
compromised entirely client-side, without a single malicious request
reaching our code.

## Content Security Policy - the highest-leverage control

- **Ship a CSP on every HTML response.** It is what turns most XSS from a
  full compromise into a blocked console error. Nothing else on this list
  buys as much.
- **Nonce or hash based. Never `unsafe-inline` on `script-src`** — it
  defeats the entire policy while leaving a header that looks like
  protection.
- **`default-src 'self'`, then widen deliberately**, naming each host and
  the reason it is there.
- **`frame-ancestors 'none'`** or an explicit allowlist. This is the
  clickjacking control; `X-Frame-Options` is only the legacy fallback.
- **`object-src 'none'` and `base-uri 'self'`** — two cheap directives
  that close plugin and base-tag injection.
- **Deploy `Content-Security-Policy-Report-Only` first**, collect real
  violations, then enforce. Enforcing first breaks the application in
  production, usually on a Friday.
- **An untested CSP is not a control.** Load the real page, open the
  console, confirm zero violations.

## Security headers - one config block, set all of them

`Strict-Transport-Security` with a long max-age and `includeSubDomains`
(the `encryption` skill already requires HSTS) ·
`X-Content-Type-Options: nosniff` ·
`Referrer-Policy: strict-origin-when-cross-origin` · `Permissions-Policy`
denying camera, microphone and geolocation unless the app uses them.

**Verify them on the deployed response with `curl -I`, never in the
config file.** CDNs, load balancers and frameworks all add and strip
headers in transit.

## XSS - escaping alone is not the control

- **Use the framework's escaping and never the escape hatch**:
  `dangerouslySetInnerHTML` (React), `v-html` (Vue),
  `bypassSecurityTrust*` (Angular), `{@html}` (Svelte). Each is a
  deliberate hole in the framework's protection. Where one is genuinely
  required, sanitize with a maintained library such as DOMPurify and
  state why in a comment.
- **Escape by context, not generically.** HTML body, attribute, URL and
  JavaScript contexts each need different treatment; one `escapeHtml()`
  used everywhere is a false sense of safety.
- **Never assemble markup by string concatenation** from user data.
- **Model output is user data** — see the `llm-app-security` skill.

## CSRF - SameSite is not a complete defence

- **`SameSite=Lax` covers the common case only.** It does not protect a
  state-changing GET, and it does not help against a compromised or
  attacker-controlled subdomain, which is same-site by definition.
- **Anti-CSRF tokens on every state-changing request**, or on a JSON API
  a strictly enforced custom header plus outright rejection of
  `application/x-www-form-urlencoded` and `text/plain`.
- **A GET must never change state.** It is also why a link preview or a
  crawler can otherwise delete a record.

## Third-party JavaScript is a supply chain nobody inventoried

- **Every analytics tag, chat widget, tag manager and font script runs
  with full page privileges.** It can read the DOM, every form field, and
  any token the page holds. Card skimming works exactly this way and
  never touches our server, so no server-side control detects it.
- **Allowlist third-party origins in the CSP.** A script that cannot be
  named in the policy does not ship.
- **Subresource Integrity on every external script and stylesheet, or
  self-host it.** A tag manager that lets a marketing user inject
  arbitrary script is a remote-code-execution path into the page with a
  friendly UI.
- **No third-party script at all on pages handling credentials, payment
  or personal data** without a stated reason.

## File uploads

- **Validate by content, not by filename or the client's Content-Type.**
  Both are attacker-controlled.
- **Store outside the served directory**, or in object storage under a
  generated key. Never serve an upload from a path where it can execute.
- **Serve downloads with `Content-Disposition: attachment` and `nosniff`,
  from a separate origin where practical**, so a stored HTML or SVG file
  cannot script against the application's origin. **SVG is an XSS
  vector, not an image.**
- **Generate the stored filename.** Never reuse the user's — path
  traversal and unicode normalization tricks live there.
- **Bound size, count and decompressed size.** The `api-security` skill
  already requires bounds; archives additionally need the decompressed
  bound or a zip bomb takes the host.
- **Access to an uploaded file is an authorization decision** like any
  other. Scope it to the authenticated principal, and scan for malware
  where users can retrieve each other's uploads.

## Verify on the real page

- **Load the deployed page and read the console.** CSP violations, mixed
  content and missing headers surface there and nowhere else.
- **Grep the built bundle** for `dangerouslySetInnerHTML`, `v-html`,
  `bypassSecurityTrust`, `{@html}` and justify every hit.
- Report which of these were exercised, as with every other verification.

## Related

- OWASP Top 10 checklist: `${CLAUDE_PLUGIN_ROOT}/references/owasp-top10.md` (categories 3, 5)
- `auth-portal` — cookie flags and token storage
- `llm-app-security` — rendering model-authored markup
- Accessibility (WCAG 2.1 AA) remains resident in CLAUDE.md
