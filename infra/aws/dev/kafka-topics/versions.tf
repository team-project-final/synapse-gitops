terraform {
  required_version = ">= 1.7.0"

  required_providers {
    kafka = {
      source  = "Mongey/kafka"
      version = "~> 0.7"
    }
  }
}

provider "kafka" {
  bootstrap_servers = var.bootstrap_servers
  tls_enabled       = true
  # MSK TLS(9094): 브로커는 Amazon Trust Services CA 체인 → 기본 시스템 신뢰스토어로 검증.
  # 별도 클라이언트 인증서 없음(TLS-only, SASL/IAM 미사용 — spec §3 B안).
}
