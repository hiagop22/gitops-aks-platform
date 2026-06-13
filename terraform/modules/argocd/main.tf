resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "argocd" {
    name       = "argocd"
    repository = "https://argoproj.github.io/argo-helm"
    chart      = "argo-cd"
    version    = var.argocd_helm_version
    namespace  = var.namespace
    
    create_namespace = true
    
    values = [
        yamlencode({
            server = {
                service = {
                    type = "ClusterIP"
                }
            }
        })
    ]

    wait = true
    timeout = 600
}

resource "argocd_application" "root_app" {
  metadata {
    name = var.cluster_name
    namespace = var.namespace
  }

  spec {
    project = "default"

    source {
      repo_url = var.repo_url
      target_revision = var.repo_revision
      path = "clusters/${var.cluster_name}"
    }

    destination {
      server = "https://kubernetes.default.svc"
      namespace = var.namespace
    }

    sync_policy {
      automated {
        prune = true
        self_heal = true
      }
    }
  }
}