---
name: encryption
description: Standard for encryption in transit and at rest. Use when creating or modifying any data store (bucket, database, volume, cache, queue, search index, warehouse, backup or snapshot), configuring TLS or certificates, choosing KMS/CMK vs provider-managed keys, hashing passwords, handling secrets on disk, or answering a client questionnaire about encryption. Also use when tempted to disable certificate verification.
---

# Encryption - In Transit and At Rest

Data is encrypted in transit and at rest, everywhere, by default. This is
the standard that OWASP screening item #2 points at. It is not a
per-project decision and does not wait for data to be classified
sensitive — classification happens later and is often wrong, so encrypt
first.

## In transit

- **TLS 1.2 minimum, TLS 1.3 preferred.** TLS 1.0/1.1 and SSL disabled.
  Modern cipher suites only.
- **NEVER disable certificate verification.** `verify=False`,
  `curl -k`, `rejectUnauthorized: false`, `InsecureSkipVerify: true`,
  and blanket trust-all handlers are prohibited in anything that is not
  a throwaway local experiment — they routinely survive into production
  and silently convert TLS into obfuscation. If a certificate does not
  validate, fix the certificate.
- **Internal traffic counts.** "It's on the private network" is not a
  trust boundary. Service-to-service, app-to-database, app-to-cache and
  app-to-queue links are encrypted too. Database connections are the
  most commonly missed one — verify the driver actually negotiates TLS
  rather than falling back.
- **No plaintext protocols**: HTTP, FTP, Telnet, rsync-over-plain,
  unauthenticated SMTP, LDAP without TLS.
- **HTTPS everywhere on web surfaces**: redirect HTTP → HTTPS, set HSTS,
  mark cookies `Secure`.
- **Email in transit**: TLS enforced; publish MTA-STS and TLS-RPT where
  the platform supports it, alongside the SPF/DKIM/DMARC requirements.

## At rest

- **Encryption ON for every store, by default**: object storage, block
  volumes, databases, search indexes, caches, queues, data warehouses,
  and log archives.
- **Backups and snapshots especially.** They are the most frequently
  forgotten copy and often the least protected — an unencrypted snapshot
  or export undoes every other control on the primary store.
- **Workstations and portable media**: full-disk encryption (FileVault,
  BitLocker) on every device that touches customer material.
- **Secrets live in a secret manager**, never in source, never in a
  committed env file, never in an IaC variable in plaintext. Files on
  disk holding credentials are mode 600 and gitignored — verify with
  `git check-ignore` before writing them.
- **Customer-managed keys (KMS/CMK)** where customer or regulated data
  is involved; provider-managed keys are acceptable for internal and
  non-sensitive stores. State which was chosen and why.
- **Enable key rotation.** Keys are stored separately from the data they
  protect, with least-privilege key policies.
- **Use vetted primitives.** No homegrown crypto, no ECB mode, no MD5 or
  SHA-1 for anything security-bearing, no unsalted hashes. Passwords use
  bcrypt, scrypt, or Argon2.
- **Never log plaintext** of encrypted fields, keys, or secrets.

## Understand what at-rest encryption actually buys

At-rest encryption defends against stolen media, misplaced snapshots,
and decommissioned disks. **It does NOT protect against an attacker
holding valid credentials or API access** — to that attacker the data
decrypts transparently. Treat it as a required baseline, never as a
substitute for access control, tenant isolation, or MFA. When a client
questionnaire asks "is the data encrypted," answer honestly and describe
the access controls too.

## Verify, do not assume

- **Confirm per resource at deploy time** that encryption is actually
  on. "The provider encrypts by default" is a claim to check against the
  live bucket, database, volume and snapshot — defaults vary by service,
  by region, and by how the resource was created.
- **Test the negotiated TLS version and cipher** on any endpoint that is
  exposed, rather than trusting configuration intent.
- **Run IaC scanners** (`checkov`, `tfsec`/`trivy config`, `tflint`) as
  part of verification — unencrypted-resource rules are exactly what
  they are good at.
- Report encryption status as part of completion when the work created
  or modified a data store.

## Related

- OWASP Top 10 checklist: `${CLAUDE_PLUGIN_ROOT}/references/owasp-top10.md` (categories 2, 7)
- `cloud-infra` — where the IaC scanners run and where CMK is chosen
- `observability` — backups exist and are restore-tested (RTO/RPO)
- `auth-portal` — password hashing in context
