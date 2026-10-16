# Public-facts register

Confirmed facts from **public vendor documentation only** — never client
material, never anything learned inside an engagement (DESIGN §7).
`research` reads this first and skips a fresh check for an entry under 90 days
old. New entries are proposed to the operator at `save` and added here by
hand in this config repository; an engagement session never writes this file.

| Fact | Official source | Checked |
|---|---|---|
| AWS Lambda Node.js 20 deprecated 2026-04-30; function create blocked 2027-07-29, update blocked 2027-08-31 | https://docs.aws.amazon.com/lambda/latest/dg/runtime-support-policy.html | 2026-10-04 |
| Amazon Bedrock AgentCore Web Search connector: default version 1.1.0 (no filters); 1.2.0 adds domain include/exclude (≤ 100 each) and published-date filters | https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-target-connector-versions.html | 2026-10-14 |
| AWS Organizations AI services opt-out policies do not cover Amazon Bedrock or Bedrock AgentCore | https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_ai-opt-out_all.html | 2026-10-04 |
