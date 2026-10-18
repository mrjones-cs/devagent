---
name: feature-flags
description: Standard for feature flags, toggles, kill switches and gradual rollouts in software we build. Use when adding, evaluating, flipping or removing a flag - server-side versus client-side evaluation, client SDK keys and bootstrap payloads, flagged-off code in public bundles, who may change a flag and how it is audited, a kill switch for a feature that calls a model, fail-safe defaults when evaluation fails, percentage or cohort rollout, and choosing a hosted flag service such as LaunchDarkly, Unleash, Flagsmith or a cloud parameter store.
---

# Feature Flags - A Remote Switch Is a Control Surface

A feature flag changes what production does without a deploy. That is the
point of it, and it is also why it matters for security: anyone who can
flip a flag can change the system's behaviour, and anything a flag hides
from a user may still be shipped to them. Treat every flag as live
configuration of a running system, with an owner, an audit trail and an
end date.

---

## When to flag, and default off

- **Flag a change when it must ship before it is released** - a feature
  merged dark, a risky migration path, a staged rollout, or anything that
  needs a kill switch. Reason: a flag separates deploying from releasing;
  if the two never need to differ, the flag is only debt.
- **A new flag defaults to off.** Reason: the safe state of an unfinished
  feature is absent. A flag that defaults on releases the feature to
  everyone the first time evaluation falls back to its default.

## Owner and removal date for every flag

- **Every flag has a named owner and a removal date when it is created.**
  Reason: flag debt is a defect. Every live flag doubles the paths through
  the code it guards, and the untested path is the one that breaks.
- **Remove the flag and its dead branch once rollout is complete.** A
  permanent operational switch (a kill switch) is the only exception, and
  it is recorded as permanent with an owner.
- **The client owns removal after delivery.** Reason: we cannot see the
  client's system once it is handed over. Any flag still live at handover
  goes into the handover manifest with its client-side owner and date (see
  `engagement-closeout`).

## Server-side evaluation for anything security-relevant

- **A flag that decides access, entitlement, pricing, data visibility or
  any security behaviour is evaluated on the server.** Reason: a flag
  evaluated in the browser is a hint, never an access control - the user
  controls the browser and can set it to anything (see
  `web-browser-security`). The server enforces the decision on every
  request (see `api-security`).
- **Evaluate per session and return only the flags that session needs.**
  Never ship the whole flag set to a client. Reason: the full set is a map
  of unreleased features, internal cohorts and targeting rules.

## Client-side exposure

- **A client SDK key and any bootstrap payload are public.** Anything in a
  browser or a mobile app can be read by its user. Scope the client key to
  flags that are safe to disclose, and keep server SDK keys server-side,
  in a secret manager (see `encryption`).
- **Customer identifiers and names never go into flag keys, variant names
  or targeting rules.** Reason: flag names travel to clients, logs and the
  flag vendor, and a key like `enable-<client>-export` names the client
  and what is being built for them - which is itself confidential.

## Flagged-off code still ships

- **In a public bundle, the dark feature is readable.** Routes, strings,
  component names, API calls and comments behind an off flag are in the
  JavaScript every visitor downloads. Reason: a flag controls execution,
  not distribution.
- **Treat anything behind a flag in a public bundle as already public.**
  If it must stay confidential, keep it out of the bundle entirely - a
  separate build or a server-delivered module - and scan the built output
  before release (see `public-release`).

## Who may flip a flag

- **The flag console and the flag store are writable only by authenticated,
  least-privilege principals, with MFA.** Reason: a flag change is a
  production change without a deploy, review or pipeline, so the console
  is a login portal to production behaviour (see `auth-portal`).
- **Every flag change is logged** - who, what, old value, new value, when -
  and the log is retained like any other audit record (see
  `observability`). Reason: an unexplained behaviour change with no record
  is indistinguishable from an attack.
- **Webhooks and streaming connections from the flag service are
  authenticated and signed**, and the receiver verifies the signature.
  Reason: an unsigned flag-update channel lets anyone who can reach it
  rewrite production behaviour.

## Security controls are never flag-gated

- **Authentication, authorization, rate limits, input validation and audit
  logging cannot be switched off by a remote flag.** Reason: a flag that can
  disable a control turns the flag console, the flag store and every key
  that writes to them into a way around that control. Roll out a new
  control behind a flag if needed, but remove the off path once it is live.

## Kill switch for features that call a model

- **Every feature that calls a model has a kill switch** that turns the
  model call off without a deploy. Reason: a prompt-injection campaign, a
  runaway cost loop or a model regression needs stopping in minutes, not
  after a release (see `llm-app-security`).
- **Its default is built into the code, not fetched,** and it **fails off**
  when the flag service is unreachable. Reason: a kill switch that needs the
  flag service to answer before it can stop anything is not a kill switch.

## Fail-safe default when evaluation fails

- **Decide the default for the case where evaluation fails** - timeout,
  network error, unknown flag, malformed response - and write it in code.
- **Security features fail closed; new features fail off.** Reason: the
  flag service being down is an ordinary event, and it must not open an
  access path or release an unfinished feature to everyone.

## Gradual rollout

- **Bucket a percentage or cohort rollout on a stable, non-personal
  identifier** - an opaque account or session ID, not an email address or
  name. Reason: a stable bucket keeps each user in one variant, and a
  non-personal one keeps personal data out of the flag vendor.
- **Tie a rollback trigger to an alert.** The symptom alert for the feature
  names the flag and the action that turns it off. Reason: a rollout with no
  rollback trigger is just a slow release.
- **A rollout flag follows the same removal rule as any flag** - owner,
  date, and removal at 100%.

## Hosted flag services are vendors

- **Each hosted flag service has an entry in the vendor register**, with a
  tier and a purpose, and its SDK is pinned to an exact version. Reason: the
  SDK runs in the product and the service decides production behaviour, so
  it is a supply-chain dependency and a sub-processor at once.
- **No personal data goes into the evaluation context without approval.**
  Reason: the context is sent to the vendor, so it is a data transfer that
  the client's data protection terms have to cover.
- **Where the client already runs a parameter store**, prefer it to a new
  vendor, and provision it through IaC (see `cloud-infra`).
- MFA on the vendor account is required (resident VENDOR ACCOUNTS).

## Related

- `web-browser-security` - client-side evaluation is a hint, not a control
- `api-security` - the server enforces the decision on every request
- `auth-portal` - the flag console is a login to production behaviour
- `observability` - flag-change audit log and rollback alerts
- `llm-app-security` - the model kill switch
- `public-release` - flagged-off code in a public bundle is public
- `cloud-infra` - parameter stores provisioned through IaC
- `encryption` - server SDK keys live in a secret manager
- `engagement-closeout` - live flags at handover, client-side owner
