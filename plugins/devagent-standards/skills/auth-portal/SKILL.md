---
name: auth-portal
description: Standard for any system with a login. Use when building, reviewing, deploying, or debugging authentication - login pages, signup, session handling, MFA enrolment or challenges, password reset and account recovery, JWT or cookie sessions, OAuth/OIDC/SAML, Cognito, Entra ID, Auth0, Identity Center, or any "temporary" / demo / internal portal that has a password. Also use when a security questionnaire asks about authentication.
---

# Authentication - Any App With a Login Portal

The moment a system has a login, the login IS the security boundary.
Everything behind it is worth exactly what it takes to get one password.
This applies to demos, POCs, internal tools and "temporary" portals —
those are the ones that end up internet-facing for months.

## Non-negotiable

- **MFA on every login portal.** No exceptions for internal tools, demos,
  or single-user systems. A portal without MFA is one phished or reused
  password away from full compromise.
- **Prefer a managed identity provider** (Cognito, Entra ID, Auth0,
  Identity Center) over hand-rolled auth. Homegrown auth means owning
  password hashing, session fixation, timing attacks, lockout, and reset
  flows forever. Choose it only with a stated reason.
- **Deny by default.** Every route authenticated unless explicitly and
  deliberately public. A public health endpoint returns liveness only —
  never version numbers, config, counts, or identifiers.
- **No self-signup** on internal or client-facing tools. Accounts are
  provisioned.

## Ship MFA in the right order — this WILL lock you out otherwise

- **Implement enrolment and challenge handling BEFORE requiring MFA.** A
  custom login form must handle the MFA-setup challenge, the TOTP
  challenge, AND new-password-required. Turning on "MFA required" against
  a user with no registered device, in a UI that cannot render the setup
  challenge, locks that user out permanently. If it is the only account,
  the system is gone.
- **Never configure "block sign-in" for users without a registered MFA
  device** unless devices are provisioned centrally in advance. It is a
  closed loop — no sign-in without MFA, no MFA registration without
  sign-in — and it surfaces as a permissions error, not a settings one.
  Use "require registration at sign-in" instead.
- **Always keep a second admin or a documented break-glass path**, on a
  physically distinct device. Two authenticators on one phone is one
  point of failure with two names.
- **Prefer phishing-resistant factors** (passkeys/WebAuthn, hardware
  keys) over TOTP; prefer TOTP over SMS. Do not enable SMS as a factor
  when a better one is available — it is the weakest link and defines
  the account's real security.

## Brute force and credential attacks

- **Exponential backoff after a small number of failures, keyed on BOTH
  the account AND the source IP.** Per-account only lets an attacker
  spray one password across many accounts; per-IP only lets a distributed
  attacker grind one account. Both, always.
- **Rate-limit at the edge in front of the auth endpoint** — but see
  "verify the control is in the path" below before assuming it applies.
- **Resist account enumeration**: identical responses and comparable
  response times for unknown-user and wrong-password. Hash against a
  fixed dummy value when the user does not exist so the timing matches.
- **Passwords: length over composition** (NIST SP 800-63B). Floor of 14+,
  no forced rotation, no composition theatre. Screen against known-breach
  lists where the platform offers it.
- **Enable compromised-credential / threat detection** if the identity
  platform provides it, and state the cost if it requires a paid tier.
- **Log every authentication event** — success, failure, lockout, MFA
  enrolment and reset — and alarm on failure spikes. Never log the
  credential, token, or MFA seed.

## Sessions and tokens

- Short-lived access tokens; refresh rather than long expiry.
- **Idle timeout AND absolute lifetime**, independently enforced.
- Server-side session state that can be revoked; logout must actually
  invalidate, not merely delete the client copy.
- Cookies `Secure` + `HttpOnly` + `SameSite`. **Do not store tokens in
  `localStorage`** — any XSS becomes full account takeover.
- **Step-up re-authentication for destructive or administrative actions**
  (user management, key rotation, deletion, payment).
- Disable authentication flows that ship the raw password to the identity
  provider when a proof-of-knowledge flow (SRP, OIDC/PKCE) is available.

## Recovery flows are the way around everything above

The reset flow is the real authentication mechanism and it is usually the
weakest one. **MFA that can be bypassed by "forgot password" is
decorative.** Every rule above is worth exactly what the recovery path
costs an attacker.

- **A reset link proves control of an inbox and nothing more.** It must
  never grant a full session on its own — re-challenge the second factor
  after the new password is set, or the account is protected by email
  alone.
- **Re-authenticate AND re-challenge MFA before** changing the email
  address, phone number, password, or enrolled factors. Those four are
  the account-takeover targets; the password is rarely the real one.
- **Notify the old address and the old factor** on any change to either,
  with an out-of-band way to object. That notification is often the only
  signal a user gets that they are being taken over.
- **Tokens single-use, short-lived, invalidated on use and on any
  password change.** Never place one in a URL that lands in a referrer
  header, an access log, or a chat preview.
- **Invalidate every existing session on reset**, or the attacker simply
  keeps the session they already had.
- **Rate-limit and log recovery exactly as login**, and treat MFA reset
  as a privileged operation. For an administrative account, require a
  human step.

## Verify, do not assume

- **Verify the control is actually in the request path.** A WAF on a CDN
  protects nothing if login goes browser→identity-provider directly and
  the API goes browser→function-URL directly. Trace the real request path
  before buying or trusting a control; a control out of the path is
  theatre with a monthly bill.
- **Never make auth enforcement conditional on configuration.** Patterns
  like `if (USER_POOL_ID) enforce()` are silent off-switches — a missing
  env var disables authentication with no error. Fail closed: if the
  auth config is absent, refuse to start.
- **Probe the deployed surface unauthenticated before calling it done.**
  Confirm real endpoints return 401/403 and that CORS is not being
  mistaken for access control — CORS is a browser convention, and
  `curl` ignores it entirely.
- **Confirm MFA state at the provider**, not from intent or memory. Some
  platforms (AWS Identity Center among them) expose no API for MFA
  settings at all, so they cannot be captured in IaC or drift-checked —
  those must be re-verified by eye at each access review, and that
  limitation stated rather than assumed away.

## Related

- OWASP Top 10 checklist: `${CLAUDE_PLUGIN_ROOT}/references/owasp-top10.md` (categories 1, 2, 7)
- `api-security` — authorizing every object, not just authenticating the caller
- `web-browser-security` — the client-side half of a login portal
- `encryption` — TLS and password hashing primitives
