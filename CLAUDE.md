# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A GitOps-driven AKS/Kubernetes platform. There is no application code, build, or test suite — the repo is entirely Terraform + Kubernetes manifests (Helm/Kustomize) consumed by ArgoCD. Treat changes as infrastructure config, validated by linting/dry-run rather than unit tests.

Only the `nonprod` environment is implemented. `bootstrap/prod/` and `clusters/prod/` exist as empty placeholders for future work — do not assume prod manifests exist elsewhere.

## Two-layer architecture

**Layer 1 — Terraform (`terraform/`)**: bootstraps a single ArgoCD instance per environment. It does *not* manage ongoing application state — its only jobs are to install the ArgoCD Helm chart and create one root `Application` resource that points at `bootstrap/<cluster_name>` in this same repo.

- `terraform/main.tf` calls `module "argocd"` (`terraform/modules/argocd/`) with vars for repo URL/revision, cluster name, namespace, and sync flags.
- `terraform/modules/argocd/argocd.tf`: creates the `argocd` namespace and installs the `argo-cd` Helm chart (server service kept as `ClusterIP`).
- `terraform/modules/argocd/applications.tf`: creates the root `Application` via `kubectl_manifest` (the `kubectl` provider, not the official ArgoCD provider) — this is intentional, done to avoid ArgoCD CRD verification issues during `terraform plan`/`apply` before the CRDs exist.
- Real variable values live in `terraform/environment/<env>/terraform.tfvars` (e.g. `cluster_name`, `enable_auto_sync`, `enable_prune`, `enable_self_heal`). The root `terraform/terraform.tfvars` is currently unused/empty — pass the environment-specific file explicitly.
- `terraform/environment/<env>/backend.tf` is currently empty (no remote backend configured); state is local in `terraform/terraform.tfstate`.
- Providers used: `kubernetes`, `helm`, `kubectl` (all pointed at `~/.kube/config`) — there is no AKS provisioning here, only in-cluster bootstrap. The actual AKS cluster is assumed to already exist (or `local/kind/cluster.yaml` is used for local dev via Kind).

**Layer 2 — GitOps (`bootstrap/`, `clusters/`)**: once the root `Application` exists, ArgoCD takes over and everything else is reconciled from Git.

- `bootstrap/<env>/` contains the `ApplicationSet`s and `AppProject`s that the root `Application` points to:
  - `platform-project.yaml` / `platform-appset.yaml`: the `platform` `AppProject` and an `ApplicationSet` using a **git directory generator** over `clusters/<env>/platform/*`. Each subdirectory found there becomes its own ArgoCD `Application` automatically — adding a new platform component is just adding a new folder under `clusters/<env>/platform/`, no appset edits needed.
  - `workloads-project.yaml` / `workloads-appset.yaml`: the `workloads` `AppProject` and an `ApplicationSet` using a **list generator** with hardcoded environments (`dev`, `qa`, `staging`). Adding a new workload environment requires editing this list and adding a matching `clusters/<env>/workloads/overlays/<newenv>/` directory.
  - `AppProject`s scope what each ApplicationSet is allowed to deploy: `platform` is broad (cluster-scoped resources, CRDs, namespaces like `istio-system`, `cert-manager`, `kube-prometheus-stack`, etc.) while `workloads` is deliberately narrow (only namespace-scoped app resources like `Deployment`/`Service`/`ConfigMap`, restricted to the `dev`/`qa`/`staging` namespaces).
- `clusters/<env>/platform/<component>/`: one folder per cluster-wide platform component (e.g. `istio/`, `kube-prometheus-stack/`), each a Helm release (via `helm-release.yaml` + `values.yaml`/`Chart.yaml`) or plain manifests, with its own `kustomization.yaml`/`namespace.yaml` as needed.
- `clusters/<env>/workloads/overlays/<workload-env>/`: Kustomize overlays per workload environment, referencing shared bases (e.g. `../../base/microservice1`) — base directories referenced here don't exist yet, so overlays are not currently deployable as-is.

## Working with this repo

- When adding a new platform component for an environment, create a new directory under `clusters/<env>/platform/` — no changes to `bootstrap/<env>/platform-appset.yaml` are needed since it auto-discovers via the git directory generator.
- When adding a new workload environment (beyond dev/qa/staging), update the `list` generator in `bootstrap/<env>/workloads-appset.yaml` AND add a corresponding `clusters/<env>/workloads/overlays/<newenv>/` directory.
- Terraform changes only affect ArgoCD's own installation/bootstrap Application, never the workloads/platform apps themselves — those are edited directly as YAML and reconciled by ArgoCD, not by Terraform.
- `*.tfstate*`, `tfplan`, and `.terraform/` are gitignored but currently present locally in `terraform/` — don't assume they're safe to commit, and don't read `terraform/.terraform/` (it's just downloaded provider/module cache, not project source).
- Don't read/traverse `.git/` directly — use `git` commands (`git log`, `git show`, etc.) instead of scanning the object database.
- Ownership boundary: developers are only meant to touch `clusters/<env>/workloads/` (app manifests/overlays). Everything else — `bootstrap/`, `clusters/<env>/platform/`, `terraform/` — is admin-only, intended to be enforced via a `CODEOWNERS` file (not yet added). Don't place namespace-scoped guardrails like `ResourceQuota`/`LimitRange`/`Role`/`RoleBinding` under `workloads/`, since that's the dev-writable tree and would let a workload change loosen its own constraints — those belong under `platform/` instead.

## Common commands

```bash
# Terraform: plan/apply the nonprod ArgoCD bootstrap (run from terraform/)
terraform init
terraform plan  -var-file=environment/nonprod/terraform.tfvars
terraform apply -var-file=environment/nonprod/terraform.tfvars

# Local cluster for development (Kind)
kind create cluster --config local/kind/cluster.yaml

# Validate/dry-run a Kustomize overlay or platform component without applying
kubectl apply --dry-run=server -k clusters/nonprod/workloads/overlays/dev
kubectl kustomize clusters/nonprod/platform/istio

# Render a platform Helm release locally for review
helm template <release> <chart> -f clusters/nonprod/platform/<component>/values.yaml
```
