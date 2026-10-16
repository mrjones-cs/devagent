# OWASP Top 10 Checklist

Shared reference for the DevAgent security skills. The standing *rule* —
screen every code change, flag findings with severity, never silently
ship a known vulnerability — is resident in `CLAUDE.md`. This file is the
checklist that rule points at.

Read this when writing or reviewing code that touches any of these areas.
Referenced by: `auth-portal`, `api-security`, `web-browser-security`,
`llm-app-security`, `encryption`, `cloud-infra`.

---

1. **Broken Access Control**: Verify authorization checks on every
   endpoint/route/resource. No client-side-only enforcement. Deny by
   default.

2. **Cryptographic Failures**: No hardcoded secrets, keys, or passwords.
   Use TLS in transit, encryption at rest for sensitive data. No weak or
   homegrown crypto (MD5/SHA1 for passwords, ECB mode, etc.).

3. **Injection**: Parameterized queries only — never string-concatenated
   SQL. Sanitize/validate all external input (query params, headers,
   file uploads, LLM output used in commands). Escape output by context
   (HTML, shell, LDAP).

4. **Insecure Design**: Flag missing rate limits, missing tenant
   isolation, or trust-boundary violations during design/planning phases.

5. **Security Misconfiguration**: No debug mode, default credentials,
   permissive CORS (`*` with credentials), or verbose error messages in
   production paths. Least-privilege IAM/service accounts.

6. **Vulnerable & Outdated Components**: When adding dependencies, prefer
   maintained libraries. Run audit tooling when available
   (`npm audit`, `pip-audit`, `cargo audit`) after dependency changes.

7. **Identification & Authentication Failures**: Proper session handling,
   secure cookie flags (HttpOnly, Secure, SameSite), password hashing
   with bcrypt/argon2/scrypt, MFA-friendly design. No credentials in URLs
   or logs.

8. **Software & Data Integrity Failures**: Pin dependency versions,
   verify signatures/checksums for downloaded artifacts, no
   deserialization of untrusted data (pickle, eval, unsafe YAML load).

9. **Security Logging & Monitoring Failures**: Log auth events and
   failures without logging secrets, tokens, or PII.

10. **Server-Side Request Forgery (SSRF)**: Validate/allowlist URLs
    before server-side fetches. Block requests to internal/metadata IP
    ranges (169.254.169.254, RFC 1918) when fetching user-supplied URLs.

---

## When to screen

- **Before writing**: Consider which categories the change touches.
- **Before completion**: Include a security check in verification — state
  which categories were reviewed and any findings.
- **On request, or for auth/payment/PII code**: Use the
  `security-engineer` agent or `/security-review` for a deeper pass.

## Reporting

Flag any finding immediately with severity (critical/high/medium/low).
Never silently ship code with a known vulnerability — fix it or surface
it to the user. Do not add exploit code, backdoors, or intentionally
weakened security even for "testing" unless explicitly directed within an
authorized security-testing context.
