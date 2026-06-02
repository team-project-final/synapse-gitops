variable "kafka_brokers" {
  description = "MSK TLS bootstrap brokers (terraform output msk_bootstrap_brokers_tls)."
  type        = string
}

variable "namespaces" {
  description = "서비스가 도는 네임스페이스."
  type        = list(string)
  default     = ["synapse-dev", "synapse-staging", "synapse-prod"]
}
