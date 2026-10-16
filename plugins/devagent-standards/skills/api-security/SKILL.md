---
name: api-security
description: Standard for APIs and any machine-facing endpoint. Use when building, exposing, reviewing, or deploying an API - REST, GraphQL, webhooks, Lambda/Function URLs, API Gateway, ALB or container ingress, service-to-service calls, API keys, rate limits, pagination, or multi-tenant data access. Also use when auditing what is publicly reachable, or when a caller can supply an identifier for a record it may not own.
---

# Public and Machine-Facing APIs

An API is a login portal without a human to notice something is wrong.
Everything in the `auth-portal` skill applies; this covers what is
specific to endpoints called by code. Most breaches here are not exotic —
they are an endpoint nobody remembered was deployed, or one that
authenticates the caller and then forgets to check the object belongs to
them.

## Know your real edge

- **Enumerate every publicly reachable entry point before claiming a
  surface is protected**: API gateways, load balancers, Lambda/Function
  URLs, container ingress, storage buckets, webhook receivers, admin
  ports, preview and staging deploys.
- **Direct-invoke endpoints bypass the CDN.** A Lambda Function URL, a
  direct ALB hostname, or a storage URL is a second front door that
  never passes the WAF, rate limiter, or geo rules attached to the CDN.
  Either put them behind the same edge or protect them at their own.
- **`AuthType: NONE` on a function URL means the internet can call it.**
  It is acceptable only when the code itself authenticates every request
  and that has been probed, not assumed.
- **Inventory beats scanning.** Undocumented, forgotten, and superseded
  endpoints ("shadow" and "zombie" APIs) are the most common breach path.
  Deprecate and DELETE old versions; do not leave `/v1` serving forever.

## Authorization is the hard part

- **Authenticate every endpoint; authorize every object.** Verifying who
  is calling is not the same as verifying that this record belongs to
  them. Broken object-level authorization is the top API vulnerability
  and it passes every auth test that only checks for a valid token.
- **Never trust a client-supplied identifier** for ownership. Scope the
  query by the authenticated principal's tenant/user, server-side. Do
  not filter in the client, and never accept `tenant_id` from the body.
- **Guard function-level authorization separately**: an authenticated
  non-admin must not reach admin routes by guessing the path or changing
  the verb.
- **Block mass assignment.** Bind explicit allowlisted fields; never
  hydrate an object straight from a request body, or a caller will set
  `role`, `is_admin`, `balance`, or `owner_id`.
- **Deny by default, and fail closed.** Missing or unparsable auth
  config must refuse to start or refuse the request — never silently
  serve unauthenticated.

## Abuse resistance

- **Rate-limit and quota per authenticated client, not just globally.** A
  global limit lets one key exhaust the service for everyone; per-client
  limits contain it and make abuse visible.
- **Bound every resource-consuming parameter**: page size, result count,
  upload size, batch length, query depth and complexity (GraphQL),
  export ranges, and request timeouts. Unbounded pagination is a denial
  of service with a friendly name.
- **Throttle expensive and money-spending operations separately** —
  anything that calls a paid model, sends email or SMS, provisions
  infrastructure, or charges a card deserves its own tighter ceiling and
  a spend cap behind it.
- **Validate input against an explicit schema** and reject unknown
  fields. Validate on the server even when the client already did.
- **Treat every server-side fetch as SSRF-prone**: allowlist destinations
  and block internal and metadata ranges (169.254.169.254, RFC 1918).

## Credentials, data and evidence

- **API keys are bearer credentials.** Never in URLs or query strings
  (they land in logs, referrers and history), never in client-side code
  or a public repo. Scope them narrowly, make them rotatable, and set a
  spend cap where the vendor allows one.
- **Prefer short-lived tokens over static keys**; prefer mTLS or signed
  requests for service-to-service over a shared secret.
- **Return only the fields the caller needs.** Do not ship a full record
  and filter in the UI — the response is the disclosure. Errors must not
  leak stack traces, SQL, internal hostnames, or whether an identifier
  exists.
- **Log every authentication and authorization failure** with enough
  context to investigate, and never log tokens, keys or payloads
  containing secrets or PII. Alarm on failure spikes and on unusual
  per-client volume.

## Verify on the deployed surface

- **Probe before declaring it done**, against the real deployment:
  unauthenticated request → 401; valid token for the wrong tenant →
  403/404; oversized and malformed payload → rejected cleanly.
- **CORS is not an access control.** It constrains browsers only; `curl`
  ignores it entirely. A permissive CORS policy is a finding, but a
  restrictive one is not protection.
- **Confirm the control is in the path** — the same rule as for login
  portals. Trace an actual request end to end rather than trusting an
  architecture diagram.

## Related

- OWASP Top 10 checklist: `${CLAUDE_PLUGIN_ROOT}/references/owasp-top10.md` (categories 1, 3, 4, 5, 10)
- `auth-portal` — authenticating the caller in the first place
- `observability` — the logging and alarm baseline referenced above
- `llm-app-security` — when an endpoint calls a paid model
