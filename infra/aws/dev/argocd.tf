resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }

  depends_on = [aws_eks_node_group.this]
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  values = [
    yamlencode({
      configs = {
        params = {
          "server.insecure" = true
        }
      }
      server = {
        service = {
          type = "ClusterIP"
        }
      }
      applicationSet = {
        enabled = true
      }
      extraObjects = [
        {
          apiVersion = "argoproj.io/v1alpha1"
          kind       = "AppProject"
          metadata = {
            name      = "synapse"
            namespace = "argocd"
          }
          spec = {
            description = "Synapse application project"
            sourceRepos = [
              "https://github.com/team-project-final/synapse-gitops.git",
            ]
            destinations = [
              {
                namespace = "synapse-*"
                server    = "https://kubernetes.default.svc"
              }
            ]
            clusterResourceWhitelist = [
              {
                group = ""
                kind  = "Namespace"
              }
            ]
            namespaceResourceWhitelist = [
              {
                group = "*"
                kind  = "*"
              }
            ]
          }
        },
        {
          apiVersion = "argoproj.io/v1alpha1"
          kind       = "ApplicationSet"
          metadata = {
            name      = "synapse-apps"
            namespace = "argocd"
          }
          spec = {
            generators = [
              {
                matrix = {
                  generators = [
                    {
                      list = {
                        elements = [
                          for service in local.service_names : {
                            service = service
                          }
                        ]
                      }
                    },
                    {
                      list = {
                        elements = [
                          for env in local.environments : {
                            env = env
                          }
                        ]
                      }
                    },
                  ]
                }
              }
            ]
            template = {
              metadata = {
                name      = "synapse-{{service}}-{{env}}"
                namespace = "argocd"
                labels = {
                  "app.kubernetes.io/part-of"  = "synapse"
                  "app.kubernetes.io/component" = "{{service}}"
                  environment                  = "{{env}}"
                }
              }
              spec = {
                project = "synapse"
                source = {
                  repoURL        = "https://github.com/team-project-final/synapse-gitops.git"
                  targetRevision = "main"
                  path           = "apps/{{service}}/overlays/{{env}}"
                }
                destination = {
                  server    = "https://kubernetes.default.svc"
                  namespace = "synapse-{{env}}"
                }
                syncPolicy = {
                  automated = {
                    prune    = true
                    selfHeal = true
                  }
                  syncOptions = ["CreateNamespace=true"]
                }
              }
            }
            templatePatch = <<-PATCH
              {{- if ne env "dev" }}
              spec:
                syncPolicy:
                  automated: null
              {{- end }}
            PATCH
          }
        },
      ]
    })
  ]
}
