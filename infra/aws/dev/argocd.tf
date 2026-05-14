resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "6.7.3"
  namespace        = "argocd"
  create_namespace = true

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  set {
    name  = "server.ingress.enabled"
    value = "false"
  }

  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "controller.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "server.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "server.resources.requests.cpu"
    value = "50m"
  }

  depends_on = [aws_eks_node_group.main]
}
