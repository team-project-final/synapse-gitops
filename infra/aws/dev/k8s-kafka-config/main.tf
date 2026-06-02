resource "kubernetes_namespace" "app" {
  for_each = toset(var.namespaces)
  metadata {
    name = each.value
  }
  lifecycle {
    # ArgoCD CreateNamespace=true와 공존 — 라벨/주석 드리프트 무시
    ignore_changes  = [metadata[0].labels, metadata[0].annotations]
    prevent_destroy = true
  }
}

resource "kubernetes_config_map" "kafka_brokers" {
  for_each = kubernetes_namespace.app
  metadata {
    name      = "kafka-brokers"
    namespace = each.value.metadata[0].name
  }
  data = {
    KAFKA_BROKERS = var.kafka_brokers
  }
}
