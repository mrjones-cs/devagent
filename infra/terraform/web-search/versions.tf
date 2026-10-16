terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # AgentCore connector targets need >= 6.63.0. Pinned exactly; re-pin
      # deliberately (see plugins/delivery/PINS.md).
      version = "6.67.0"
    }
  }
  # No backend block: configure state storage your own way (an encrypted,
  # versioned bucket with locking is recommended). Local state works for a trial.
}
