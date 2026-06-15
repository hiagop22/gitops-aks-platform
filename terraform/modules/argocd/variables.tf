variable "argocd_helm_version" {
  type = string
}

variable "repo_url" {
  type = string
}

variable "repo_revision" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "namespace" {
  type = string
}

variable "enable_auto_sync" {
  type = bool
}

variable "enable_prune" {
  type = bool
}

variable "enable_self_heal" {
  type = bool
}