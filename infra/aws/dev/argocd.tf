locals {
  argocd_values = {
    global = {
      domain = ""
    }
    configs = {
      params = {
        "server.insecure" = false
      }
      cm = {
        "timeout.reconciliation" = "180s"
      }
    }
    server = {
      replicas  = 3
      extraArgs = []
      service = {
        type = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type"                              = "external"
          "service.beta.kubernetes.io/aws-load-balancer-scheme"                            = "internet-facing"
          "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"                   = "ip"
          "service.beta.kubernetes.io/aws-load-balancer-backend-protocol"                  = "ssl"
          "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
        }
      }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }
    controller = {
      replicas = 1
      resources = {
        requests = { cpu = "200m", memory = "512Mi" }
        limits   = { cpu = "1000m", memory = "1Gi" }
      }
    }
    repoServer = {
      replicas = 2
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }
    applicationSet = {
      replicas = 2
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { cpu = "200m", memory = "256Mi" }
      }
    }
    "redis-ha" = {
      enabled = true
    }
    redis = {
      enabled = false
    }
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "6.7.3"
  namespace        = "argocd"
  create_namespace = true

  values = [yamlencode(local.argocd_values)]

  timeout = 900

  depends_on = [aws_eks_node_group.main]
}

output "argocd_namespace" {
  value       = helm_release.argocd.namespace
  description = "ArgoCD가 설치된 네임스페이스"
}
