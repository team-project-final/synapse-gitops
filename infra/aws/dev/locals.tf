locals {
  name = "${var.project}-${var.environment}"

  service_names = [
    "platform-svc",
    "engagement-svc",
    "knowledge-svc",
    "learning-card",
    "learning-ai",
  ]

  environments = ["dev", "staging", "prod"]

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "synapse-gitops"
  }
}
