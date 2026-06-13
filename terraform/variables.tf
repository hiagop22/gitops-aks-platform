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