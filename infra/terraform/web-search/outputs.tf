output "search_gateway_url" {
  description = "MCP endpoint for ~/.config/devagent/web-search.json. Requests are signed with SigV4, service name bedrock-agentcore."
  value       = aws_bedrockagentcore_gateway.search.gateway_url
}

output "search_gateway_arn" {
  description = "Gateway ARN, for the caller's IAM policy."
  value       = aws_bedrockagentcore_gateway.search.gateway_arn
}

output "caller_policy_arn" {
  description = "Customer-managed policy granting InvokeGateway on this gateway only (null when create_caller_policy is false)."
  value       = var.create_caller_policy ? aws_iam_policy.caller[0].arn : null
}

output "caller_policy_json" {
  description = "The same least-privilege statement as JSON, for inline or permission-set use."
  value       = data.aws_iam_policy_document.caller.json
}
