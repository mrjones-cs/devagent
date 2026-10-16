# DevAgent

**Guardrails, engineering standards and a delivery workflow for Claude Code**,
built for teams that deliver software under real security and confidentiality
obligations.

DevAgent is three things that work together:

| Part | What it is | Installed by |
| --- | --- | --- |
| **Resident rules** | A `CLAUDE.md` template (615 lines, ~6.6k tokens, loaded on every turn): the prohibitions and rules Claude must carry on every turn (confidentiality, toolchain security, verification) | `./install.sh` |
| **`devagent-standards`** plugin | Thirteen on-demand skills (auth, APIs, browser and LLM security, encryption, cloud, observability, documents, breach response, verification, close-out, public release) plus **`devagent-guard`**: hooks that check every tool call and deny or ask on dangerous ones | `/plugin install` |
| **`delivery`** plugin | A nine-step workflow, `load → brainstorm → design → research → spec-panel → workflow → build → save` (and `plan`, which chains design to workflow), where every step writes a markdown record, and a task is ticked only with evidence a script recorded | `/plugin install` |

It is a guard rail, not a sandbox: pattern matching stops accidents and
injected instructions, not a determined adversary. See [SECURITY.md](SECURITY.md).

DevAgent is an independent project, not affiliated with or endorsed by Anthropic.

---

## Requirements

- [Claude Code](https://code.claude.com) (tested against the version pinned in
  `plugins/delivery/PINS.md`), with the Anthropic API or Amazon Bedrock
- `python3` 3.11 or newer, `git`, `bash`
- Optional: [`uv`](https://docs.astral.sh/uv/) to run the test suites with
  coverage; the AWS CLI v2 and an AWS account for web search (see
  [Web search](#web-search-optional))

macOS and Linux. Every script is standard-library Python or bash: nothing is
installed from a package registry to run DevAgent.

## Quick start

```bash
git clone https://github.com/mrjones-cs/devagent.git ~/devagent
cd ~/devagent
./install.sh
```

`install.sh` copies `templates/CLAUDE.md` to `~/.claude/CLAUDE.md` if you have
none (an existing file is never overwritten), links the notes template,
creates an optional client-brand list (mode 600), and writes one permission
rule for the research script. Then, inside Claude Code:

```
/plugin marketplace add https://github.com/mrjones-cs/devagent
/plugin install devagent-standards@devagent
/plugin install delivery@devagent
```

Run `./install.sh` once more, so the research rule names the path the plugin
actually loads from, and start a **new** session. Check it took:

```bash
./install.sh --check     # exits 1 if the resident rules are not loaded
```

In Claude Code, `/context` should show:

- memory files ~6.6k tokens (was close to zero before the install)
- the 13 devagent-standards skills and the 9 delivery skills
- and `/hooks` should list the devagent-guard and delivery hooks

**Next: make the rules yours.** Open `~/.claude/CLAUDE.md`, fill in the
ORGANISATION block and replace every `[PLACEHOLDER]`. To keep your rules in a
private repository of your own instead, link it:

```bash
./install.sh --rules ~/my-rules/CLAUDE.md
```

[docs/CUSTOMIZING.md](docs/CUSTOMIZING.md) explains which rules must stay
resident and how to add standards of your own.

## Updating

```
/plugin update devagent-standards
/plugin update delivery
```

then run `./install.sh` again. A plugin update moves it to a new folder (the
path carries the version), and the research permission rule names the exact
path, so the script only runs without a prompt once the rule is rewritten.
`./install.sh --check` tells you if it is out of date. To update the installer,
templates and tests themselves, `git pull` in your clone.

## Your first feature

```
/delivery:load                          start of every session: a structured briefing
/delivery:brainstorm rate-limiter       requirements: goals, data handled, constraints, tier
/delivery:plan rate-limiter             design → research → review panel → implementation plan
/delivery:build rate-limiter            one task at a time, each verified and committed
/delivery:save rate-limiter             end of every session: notes, lessons, handover checks
```

Each step writes into `docs/plans/<feature>/` in your project:
`01-requirements.md` … `05-implementation.md`, plus `evidence/` logs written by
`run-verify`, never by the model. Small changes use tier **S** (brainstorm,
then a short plan and build); new systems use tier **L** (every step, an
eight-lens review). [examples/guard-report/](examples/guard-report/) is a
complete real run, including a build killed mid-task and resumed.

## What the guard does

`devagent-guard` runs on every tool call. In the default **enforce** mode each
rule denies the call or stops for your approval:

| Rule | Catches | Action |
| --- | --- | --- |
| `pipe-to-shell` | `curl … \| bash`, `bash <(curl …)` | deny |
| `tls-disabled` | `curl -k`, `--insecure`, `NODE_TLS_REJECT_UNAUTHORIZED=0`; code writing `verify=False`, `rejectUnauthorized: false` | deny |
| `going-public` | making a repo, gist or bucket public | ask |
| `unpinned-install` | `npx -y pkg` with no version, `@latest`, unpinned `uvx`/`pip` git installs, `uv run --with pkg` without `==` | ask |
| `credential-read` | reading `.env`, `~/.aws/credentials`, private keys, `~/.claude.json` | deny (Read) / ask (shell) |
| `git-push` | `git push`, `gh pr create` while a delivery build holds its lock | deny |
| `aws-outside-profile` | mutating `aws` calls (`create-*`, `put-*`, `delete-*` …); reads pass | ask |
| `audit-tamper` | deleting, moving, linking, `chmod`-ing or rewriting the audit log | deny |
| `agent-config-write` | writes to Claude Code settings, `.mcp.json`, agent configuration | ask |
| `fetch-allowlist` | fetching pages off official domains while research is active | deny |

Command parsing is quote-aware: a commit message that *mentions* `curl -k` is
data, while `sh -c`, `eval`, `$(…)`, backticks and heredoc bodies are still
checked as commands. Every tool call is written to an audit log under
`~/.claude/devagent-audit/<project>/` (700/600, secrets redacted, paths only,
90-day retention). Review it with:

```bash
python3 -I scripts/guard-report.py              # --since YYYY-MM-DD, --engagement NAME
```

`DEVAGENT_GUARD_MODE=warn` rolls back to warn-only locally; any other value
falls back to the shipped default, so a typo cannot switch enforcement off.

## Web search (optional)

The `research` step confirms facts on current sources, so the design does not
rest on the model's training cutoff. It works **without any search service**:
each fact is confirmed by fetching the official page directly, and the guard
limits fetches to official domains while research runs.

To add search, DevAgent uses AWS Bedrock AgentCore Web Search through a
gateway in your own AWS account. [`infra/terraform/web-search/`](infra/terraform/web-search/)
creates it; then write its URL where the script reads it:

```bash
mkdir -p ~/.config/devagent
(umask 077 && printf '{"url": "%s"}\n' "$(terraform -chdir=infra/terraform/web-search output -raw search_gateway_url)" \
  > ~/.config/devagent/web-search.json)
```

Queries are checked against a per-project deny-list (`.delivery/deny-list`)
before they leave the machine. Read the AgentCore data-use terms first: see
[docs/DESIGN.md](docs/DESIGN.md) §6.

## Repository layout

```
templates/                     CLAUDE.md template, notes template, client-list example
plugins/devagent-standards/    13 skills, OWASP checklist, devagent-guard hooks
plugins/delivery/              9 step skills, 4 agents, 11 review lenses, step files,
                               templates, scripts (check-plan, run-verify, web-search,
                               build-*, briefing), hooks, PINS.md
scripts/                       check-skills.py, guard-report.py, every test suite
tests/fixtures/                plan-grammar fixtures (good and deliberately bad)
examples/guard-report/         a complete delivery record
infra/terraform/web-search/    optional search gateway
docs/                          DESIGN (normative), ARCHITECTURE, CUSTOMIZING
```

## Checks

Everything runs in seconds, needs no network, and runs in CI on every push:

```bash
python3 scripts/check-skills.py        # structure, cross-references, stubs, prose figures, pins
bash scripts/test-check-skills.sh      # the checker's own negative tests
bash scripts/test-install.sh           # installer, against a throwaway HOME
bash scripts/test-hooks.sh             # every guard rule: must fire, look-alikes must not
bash scripts/test-check-plan.sh        # plan grammar
bash scripts/test-run-verify.sh        # evidence writer
bash scripts/test-web-search.sh        # search client, offline
bash scripts/test-delivery-hooks.sh    # briefing and plan-check hook
bash scripts/test-build-protocol.sh    # build lock, scope check, integrate
bash scripts/test-guard-report.sh      # audit report
```

Any test script takes `COVER=1` to report line and branch coverage (needs `uv`).
`scripts/test-delivery-smoke.sh --record` checks a real install in live
headless sessions; it needs Claude Code signed in and costs a few cents.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues: [SECURITY.md](SECURITY.md).
Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE). Parts of three delivery agents are adapted from the
SuperClaude Framework, also MIT; see `plugins/delivery/THIRD-PARTY-NOTICES`.
