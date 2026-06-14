variable "argocd_helm_version" {
  description = "Version of the ArgoCD Helm chart to deploy"
  type        = string
  default     = "9.5.19"
}

variable "repo_url" {
  description = "Git repository URL for ArgoCD application"
  type        = string
}

variable "repo_revision" {
  description = "Git revision (branch, tag, or commit) to deploy"
  type        = string
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (used for ArgoCD application name and path)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace where ArgoCD will be deployed"
  type        = string
}

variable "enable_auto_sync" {
  description = "Whether to enable automated sync for ArgoCD application"
  type        = bool
}

variable "enable_prune" {
  description = "Whether to enable resource pruning (deletion) in automated sync"
  type        = bool
}

variable "enable_self_heal" {
  description = "Whether to enable self-healing in automated sync"
  type        = bool
}