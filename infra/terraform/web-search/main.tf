# An AgentCore Gateway exposing the AWS Web Search connector, for the DevAgent
# research step. Holds no data and has no idle charge (billed per call; check
# current AgentCore pricing). Apply it in a tooling account that holds no
# client data. Teardown: terraform destroy.
#
# DATA RULE: no client or project specifics in search queries - the
# web-search script enforces a per-project deny-list before sending. Read the
# AgentCore service terms on content use before relying on it. Search results
# are untrusted input that may carry injected instructions.

provider "aws" {
  region              = var.region
  allowed_account_ids = length(var.allowed_account_ids) > 0 ? var.allowed_account_ids : null

  default_tags {
    tags = var.tags
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# ---------------------------------------------------------------- gateway role
# The role AgentCore assumes to call the search backend. Trust is limited to
# gateways in this account and Region (the confused-deputy conditions from the
# AWS guide).
data "aws_iam_policy_document" "gateway_assume" {
  statement {
    sid     = "AllowAgentCoreToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:bedrock-agentcore:${var.region}:${local.account_id}:gateway/*"]
    }
  }
}

resource "aws_iam_role" "search_gateway" {
  name               = "${var.name_prefix}-search-gateway"
  description        = "Service role for the DevAgent AgentCore web search gateway"
  assume_role_policy = data.aws_iam_policy_document.gateway_assume.json
}

# Exactly the two actions the AWS guide lists for the Web Search connector.
data "aws_iam_policy_document" "gateway" {
  statement {
    sid       = "InvokeGateway"
    effect    = "Allow"
    actions   = ["bedrock-agentcore:InvokeGateway"]
    resources = [aws_bedrockagentcore_gateway.search.gateway_arn]
  }

  statement {
    sid       = "InvokeWebSearch"
    effect    = "Allow"
    actions   = ["bedrock-agentcore:InvokeWebSearch"]
    resources = ["arn:aws:bedrock-agentcore:${var.region}:aws:tool/web-search.v1"]
  }
}

resource "aws_iam_role_policy" "gateway" {
  name   = "web-search"
  role   = aws_iam_role.search_gateway.id
  policy = data.aws_iam_policy_document.gateway.json
}

# ---------------------------------------------------------------- gateway
# Inbound auth is AWS_IAM (SigV4): a caller needs AWS credentials in this
# account with bedrock-agentcore:InvokeGateway on this gateway. There is no
# public or anonymous path and no API key to leak.
resource "aws_bedrockagentcore_gateway" "search" {
  name            = "${var.name_prefix}-search"
  description     = "AWS web search for the DevAgent research step. No client material in queries."
  protocol_type   = "MCP"
  authorizer_type = "AWS_IAM"
  role_arn        = aws_iam_role.search_gateway.arn
}

resource "aws_bedrockagentcore_gateway_target" "web_search" {
  name               = "web-search"
  description        = "AWS-operated Web Search connector"
  gateway_identifier = aws_bedrockagentcore_gateway.search.gateway_id

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      connector {
        configuration {
          name = "WebSearch"
          # Must be present even when empty: without it the provider sends no
          # configurations and the API answers "Connector configurations must
          # not be empty". A target-level domain include/exclude list goes here.
          parameter_values = jsonencode({})
        }

        source {
          connector_id = "web-search"
          version      = var.web_search_connector_version
        }
      }
    }
  }

  # The backend call is authorized per request against the role policy.
  depends_on = [aws_iam_role_policy.gateway]
}

# ---------------------------------------------------------------- caller policy
# Attach to the identity that runs research (a role or permission set used only
# for Claude Code is best). It grants this one gateway and nothing else.
data "aws_iam_policy_document" "caller" {
  statement {
    sid       = "InvokeDevAgentSearchGateway"
    effect    = "Allow"
    actions   = ["bedrock-agentcore:InvokeGateway"]
    resources = [aws_bedrockagentcore_gateway.search.gateway_arn]
  }
}

resource "aws_iam_policy" "caller" {
  count       = var.create_caller_policy ? 1 : 0
  name        = "${var.name_prefix}-search-caller"
  description = "InvokeGateway on the DevAgent search gateway only"
  policy      = data.aws_iam_policy_document.caller.json
}
