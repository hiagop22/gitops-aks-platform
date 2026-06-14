resource "kubernetes_manifest" "root_app" {
  manifest = {
    "apiVersion" = "argoproj.io/v1alpha1"
    "kind" = "Application"
    "metadata" = {
      "name" = var.cluster_name
      "namespace" = var.namespace
    }
    "spec" = {
      "project" = "default"
      "source" = {
        "repoURL" = var.repo_url
        "targetRevision" = var.repo_revision
        "path" = "clusters/${var.cluster_name}"
      }
      "destination" = {
        "server" = "https://kubernetes.default.svc"
        "namespace" = var.namespace
      }
      "syncPolicy" = var.enable_auto_sync ? {
        "automated" = {
          "prune"    = var.enable_prune
          "selfHeal" = var.enable_self_heal
        }
      } : null
    }
  }
}