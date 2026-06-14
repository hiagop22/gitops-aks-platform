module "argocd" {
  source = "./modules/argocd"

  argocd_helm_version = var.argocd_helm_version
  repo_url            = var.repo_url
  repo_revision       = var.repo_revision
  cluster_name        = var.cluster_name
  namespace           = var.namespace
  enable_auto_sync    = var.enable_auto_sync
  enable_prune        = var.enable_prune
  enable_self_heal    = var.enable_self_heal
}