provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

provider "argocd" {
  port_forward_with_namespace = var.namespace
  insecure = true
  plain_text = true
}