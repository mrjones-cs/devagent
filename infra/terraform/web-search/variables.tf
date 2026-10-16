variable "region" {
  description = "Region for the gateway. AgentCore Web Search must be available there."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for every resource name."
  type        = string
  default     = "devagent"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name_prefix))
    error_message = "Use lower-case letters, digits and hyphens, starting with a letter."
  }
}

variable "web_search_connector_version" {
  description = "Pinned Web Search connector version. 1.2.0 adds per-request domain and published-date filters, which the web-search script relies on. Re-pin deliberately; do not drop the pin."
  type        = string
  default     = "1.2.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.web_search_connector_version))
    error_message = "Pin an exact connector version such as 1.2.0."
  }
}

variable "allowed_account_ids" {
  description = "If set, the provider refuses to run against any other account - a guard against applying into the wrong one. Recommended."
  type        = list(string)
  default     = []
}

variable "create_caller_policy" {
  description = "Create a customer-managed IAM policy granting InvokeGateway on this gateway only, to attach to the identity that runs research."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = { managed_by = "terraform", module = "devagent-web-search" }
}
