# Pins

Every version DevAgent itself depends on, in one place. Re-pin deliberately,
for example by running `/delivery:research` against this file at a regular
review; never drift to latest. `scripts/check-skills.py` asserts that each
value here matches the place it is set.

Pins on your own machine (your models, MCP servers, the Terraform CLI) belong
in your own records, not here.

| Pin | Value | Set in | Why this version | Deprecation / release page | Last reviewed |
|---|---|---|---|---|---|
| delivery-plugin | 1.1.0 | `plugins/delivery/.claude-plugin/plugin.json` | released with devagent-standards under one repo tag | this repo's tags | 2026-10-20 |
| standards-plugin | 1.1.0 | `plugins/devagent-standards/.claude-plugin/plugin.json` | released with delivery under one repo tag | this repo's tags | 2026-10-20 |
| claude-code | 2.1.300 | `.github/workflows/check.yml` | version the plugins were validated against; CI runs `claude plugin validate --strict` on exactly this | https://code.claude.com/docs/en/changelog | 2026-10-16 |
| web-search-connector | 1.2.0 | `infra/terraform/web-search/variables.tf` | 1.2.0 adds domain and published-date filters, which `web-search` uses; the default version has none | https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-target-connector-versions.html | 2026-10-16 |
| terraform-provider-aws | 6.67.0 | `infra/terraform/web-search/versions.tf` | AgentCore connector targets need >= 6.63.0 | https://registry.terraform.io/providers/hashicorp/aws | 2026-10-16 |
| uv (CI, test-only) | 0.9.21 | `.github/workflows/check.yml` | runs the pinned coverage tool | https://github.com/astral-sh/uv/releases | 2026-10-16 |
| coverage (test-only) | 7.16.2 | `scripts/test-guard-report.sh` | measures the 80% line and branch floor; run as `uv run --with 'coverage==7.16.2'`, never installed globally | https://pypi.org/project/coverage/ | 2026-10-16 |
