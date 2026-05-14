resource "kubernetes_namespace" "infra" {
  metadata {
    name = "synapse-infra"
  }

  depends_on = [aws_eks_node_group.this]
}

resource "kubernetes_deployment" "schema_registry" {
  metadata {
    name      = "schema-registry"
    namespace = kubernetes_namespace.infra.metadata[0].name
    labels = {
      app = "schema-registry"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "schema-registry"
      }
    }

    template {
      metadata {
        labels = {
          app = "schema-registry"
        }
      }

      spec {
        container {
          name  = "schema-registry"
          image = "confluentinc/cp-schema-registry:7.6.1"

          port {
            container_port = 8081
          }

          env {
            name  = "SCHEMA_REGISTRY_HOST_NAME"
            value = "schema-registry"
          }

          env {
            name  = "SCHEMA_REGISTRY_LISTENERS"
            value = "http://0.0.0.0:8081"
          }

          env {
            name  = "SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS"
            value = "SSL://${join(",SSL://", split(",", aws_msk_cluster.this.bootstrap_brokers_tls))}"
          }

          env {
            name  = "SCHEMA_REGISTRY_KAFKASTORE_SECURITY_PROTOCOL"
            value = "SSL"
          }

          readiness_probe {
            http_get {
              path = "/subjects"
              port = 8081
            }
            initial_delay_seconds = 20
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/subjects"
              port = 8081
            }
            initial_delay_seconds = 30
            period_seconds        = 20
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "schema_registry" {
  metadata {
    name      = "schema-registry"
    namespace = kubernetes_namespace.infra.metadata[0].name
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "schema-registry"
    }

    port {
      name        = "http"
      port        = 8081
      target_port = 8081
    }
  }
}
