# Optional: web search gateway

Creates an AWS Bedrock AgentCore **Gateway** with the AWS-operated **Web
Search** connector as its target, for the DevAgent `research` step. Without
it, research still works: it confirms facts by fetching official pages.

Resources: the gateway (inbound auth `AWS_IAM`, no public path), its Web
Search target pinned to a connector version, the service role AgentCore
assumes, and (by default) a caller policy granting `InvokeGateway` on this
gateway only. Nothing stores data; billing is per call.

## Before you apply

- **Use a tooling account that holds no client data.** If you use AWS
  Organizations, a dedicated account with an SCP allow-list is recommended.
- **Read the AgentCore terms on content use.** At the time of writing AWS may
  use and store query content to improve the service, with no opt-out. The
  `web-search` script refuses any query containing a term from the project's
  `.delivery/deny-list`; keep queries generic.
- Confirm AgentCore Web Search is available in your Region (default
  `us-east-1`) and check current pricing.

## Apply

```bash
cd infra/terraform/web-search
terraform init                    # add your own backend first for shared use
terraform plan -var 'allowed_account_ids=["111122223333"]'
terraform apply -var 'allowed_account_ids=["111122223333"]'
```

`allowed_account_ids` makes the provider refuse any other account, which
guards against applying into the wrong one. The provider version is pinned and
`.terraform.lock.hcl` records its hashes for Linux and macOS.

## Connect DevAgent to it

1. **Give the research identity the caller policy.** Attach
   `caller_policy_arn` (or the `caller_policy_json` statement) to the AWS
   identity Claude Code runs research as. A role or permission set used only
   for Claude Code is best: it should be able to invoke models and this one
   gateway, nothing else.
2. **Tell the script where the gateway is** (mode 600):

   ```bash
   mkdir -p ~/.config/devagent
   (umask 077 && printf '{"url": "%s"}\n' "$(terraform output -raw search_gateway_url)" \
     > ~/.config/devagent/web-search.json)
   ```

3. **Point it at your profile**, if it is not your default:
   `export DEVAGENT_SEARCH_PROFILE=<profile>` (or pass `--profile`).
4. **Check:** `plugins/delivery/scripts/web-search "AWS Lambda runtime deprecation" --max 3`
   from the repository root. Exit codes are listed in `docs/DESIGN.md` §6.2;
   7 means not configured.

## Inputs

| Variable | Default | Purpose |
| --- | --- | --- |
| `region` | `us-east-1` | Gateway Region |
| `name_prefix` | `devagent` | Prefix for every resource name |
| `web_search_connector_version` | `1.2.0` | Pinned connector; 1.2.0 adds the domain and date filters the script uses |
| `allowed_account_ids` | `[]` | Refuse to run against any other account (recommended) |
| `create_caller_policy` | `true` | Create the least-privilege caller policy |
| `tags` | `{managed_by, module}` | Tags on every resource |

## Outputs

`search_gateway_url` · `search_gateway_arn` · `caller_policy_arn` ·
`caller_policy_json`

## Teardown

`terraform destroy`. There is no data to preserve.
