variable "bootstrap_servers" {
  description = "MSK TLS bootstrap brokers (9094). 인프라 state의 msk_bootstrap_brokers_tls output에서 취득."
  type        = list(string)
}

variable "replication_factor" {
  description = "토픽 복제 계수. MSK 브로커 수(dev tfvars msk_broker_count=2) 이하여야 생성 성공 → dev=2."
  type        = number
  default     = 2
}

variable "min_insync_replicas" {
  description = "min.insync.replicas. aws_msk_configuration(min.insync.replicas=2)와 정합."
  type        = string
  default     = "2"
}
