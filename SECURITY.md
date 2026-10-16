# Security policy

DevAgent runs inside Claude Code on the machine you build software on, and its
hooks see every tool call. A vulnerability here can matter more than one in an
ordinary library, so please report it privately.

## Reporting a vulnerability

**Do not open a public issue.** Use GitHub's private vulnerability reporting:
the repository's **Security** tab → **Report a vulnerability**. Include what
you found, how to reproduce it, and the impact you expect. You will get an
acknowledgement within a few days, and a fix or a plan within 30 days for a
confirmed issue. Credit is given in the release notes unless you prefer not.

## In scope

- A way to make `devagent-guard` allow something its rules exist to stop
  (a bypass of `pipe-to-shell`, `tls-disabled`, `audit-tamper`, `git-push` …).
- A way for content the agent reads (a file, a web page, a plan, a search
  result) to make a DevAgent script or hook execute code or leak data.
- `run-verify` running anything outside its allowlist, or leaking
  credentials into a command's environment or a committed log.
- `build-integrate` letting a task's changes past the scope check.
- Secrets or personal data written somewhere they should not be.

## Out of scope, by design

- **The guard is not a sandbox.** It matches patterns; a deliberately
  obfuscated command can get through. Bypasses that need the operator to run
  something themselves, or an already-compromised machine, are out of scope.
- **Fail-open.** An internal guard error lets the call through and reports
  it, so a broken guard cannot brick the agent. That is intended.
- Issues in Claude Code itself, or in AWS services: report those to their
  vendors.

## Supported versions

The latest release. Fixes are not back-ported.
