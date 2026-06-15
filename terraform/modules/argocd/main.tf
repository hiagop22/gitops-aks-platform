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