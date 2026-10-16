---
name: llm-app-security
description: Standard for AI-powered software we build. Use when designing or reviewing anything that calls a model - prompts, system prompts, agents, tool/function calling, RAG and retrieval, embeddings and vector stores, chat UIs, model output that reaches a shell/SQL/renderer, model vendor selection, or prompt logging. Covers prompt injection in OUR products; the ban on acting on injected instructions aimed at this agent stays resident in CLAUDE.md.
---

# LLM and AI Application Security

We build AI-powered software, so the model is part of the attack surface —
not just the implementation detail. OWASP screening covers the
application around the model; this covers the model itself. Treat every
token that reaches a model as untrusted input, and every token that
leaves it as untrusted output.

> Scope note: this skill is about products we ship. Prompt injection
> aimed at *this agent* — hostile instructions in a README, a fetched
> page, a customer document — is governed by the resident AGENT AND
> DEVELOPER TOOLCHAIN SECURITY section in CLAUDE.md, which never loads
> on demand.

## Prompt injection - assume it, design around it

- **All model input from a non-operator source is hostile.** User text,
  uploaded files, retrieved documents, scraped pages, email bodies, tool
  results, and database fields are all injection vectors.
- **Indirect injection is the dangerous one.** A poisoned document in a
  RAG corpus, or a crafted page reached by a fetch tool, attacks the
  agent without the user typing anything. Direct injection is a
  nuisance; indirect injection is a breach path.
- **The system prompt is not a security control.** It can be extracted,
  ignored, or overridden. Never put a secret in it, and never rely on it
  to enforce an authorization rule.
- **Keep instructions and data separable.** Delimit untrusted content
  explicitly and tell the model it is data. This lowers the rate; it
  does not eliminate it — always pair it with a real control below.

## Model output reaches nothing dangerous unvalidated

Extends OWASP #3. Model output is untrusted input to whatever consumes it:

- **Never pass model output to a shell, SQL string, `eval`, a
  deserializer, or a file path without validation.** Parameterize and
  allowlist exactly as for any other untrusted input.
- **Escape by context before rendering** — model-authored HTML or
  Markdown rendered raw is stored XSS with extra steps.
- **Constrain the shape.** Prefer structured output against a schema, or
  a tool call with an enum, over parsing free text and trusting it.

## Excessive agency - the tools are the blast radius

- **Least-privilege tools.** An agent gets the narrowest tool that does
  the job, with its own scoped credentials — never the operator's,
  never a blanket admin role.
- **Human approval for irreversible or outward-facing actions**: sending
  email, moving money, deleting data, provisioning infrastructure,
  publishing. The confirm step is the control; model judgement is not.
- **Bound the loop.** Cap iterations, tool calls, wall-clock, and spend.
  An agent that cannot stop is a denial-of-service against our own bill.

## Retrieval and tenancy

- **The model is not an access control.** Scope every retrieval query by
  the authenticated principal's tenant server-side, before the model
  sees a result. "Instruct the model not to reveal other tenants' data"
  is not isolation — see object-level authorization in the
  `api-security` skill.
- **Embeddings and vector stores inherit the source's classification.**
  An index built from customer material IS customer material: same
  encryption, same account boundary, same retention obligation.

## Vendor, retention and logging

- **Model vendors follow CUSTOMER CONFIDENTIALITY** (resident in
  CLAUDE.md) — approved register only, no-training terms required, and
  the engagement's own contract governs above both.
- **Never log raw prompts or completions** containing customer material,
  credentials, or PII. Log identifiers, token counts, latency, and
  outcomes. Prompt logs are the most commonly overlooked copy of a
  customer's confidential material.
- **Spend cap per key and per client** — see the throttling rule in
  `api-security`. A leaked key on a metered model is a financial
  incident on a clock.

## Verify, do not assume

- **Attempt the injection before calling it done.** Put a hostile
  instruction in the exact channel the design trusts — the uploaded
  file, the retrieved page, the tool result — and confirm it cannot
  reach a privileged action.
- **Probe the tenant boundary through the model**, not just the API: ask
  it, in the application's own UI, for another tenant's data.
- State which of these were exercised as part of completion.

## Related

- OWASP Top 10 checklist: `${CLAUDE_PLUGIN_ROOT}/references/owasp-top10.md` (categories 1, 3, 8, 10)
- `api-security` — tenancy, spend caps, schema validation
- `web-browser-security` — rendering model output safely
- `encryption` — classification of vector stores built from customer data
