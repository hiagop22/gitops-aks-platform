# gitops-aks-platform

GitOps-driven AKS/Kubernetes platform built with Terraform, ArgoCD, Helm, and Kustomize. Terraform bootstraps a single ArgoCD instance per environment; everything after that is reconciled from Git.

Only the `nonprod` environment is implemented today. `bootstrap/prod/` and `clusters/prod/` exist as empty placeholders for future work.

## Architecture

**Layer 1 — Terraform (`terraform/`)**
Bootstraps ArgoCD: installs the `argo-cd` Helm chart and creates a single root `Application` that points at `bootstrap/<cluster_name>` in this same repo. It does not manage application state beyond that.

**Layer 2 — GitOps (`bootstrap/`, `clusters/`)**
Once the root `Application` exists, ArgoCD takes over:
- `bootstrap/<env>/platform-appset.yaml` — `ApplicationSet` using a git **directory generator** over `clusters/<env>/platform/*`. Each subdirectory found there becomes its own `Application` automatically.
- `bootstrap/<env>/workloads-appset.yaml` — `ApplicationSet` using a **list generator** with hardcoded environments (`dev`, `qa`, `staging`).
- `bootstrap/<env>/platform-project.yaml` / `workloads-project.yaml` — `AppProject`s scoping what each `ApplicationSet` may deploy. `platform` is broad (cluster-scoped resources, CRDs, namespaces); `workloads` is deliberately narrow (namespace-scoped app resources only, restricted to `dev`/`qa`/`staging`).

## Repository structure

```text
gitops-aks-platform/
├── terraform/                       # Bootstraps ArgoCD (per environment)
│   ├── main.tf                      # Calls module "argocd"
│   ├── variables.tf / providers.tf / versions.tf
│   ├── environment/nonprod/         # terraform.tfvars, backend.tf
│   └── modules/argocd/
│       ├── argocd.tf                # argocd namespace + Helm release
│       ├── applications.tf          # Root Application (kubectl_manifest)
│       ├── variables.tf
│       └── versions.tf
│
├── bootstrap/
│   ├── nonprod/
│   │   ├── platform-appset.yaml     # Directory generator -> clusters/nonprod/platform/*
│   │   ├── platform-project.yaml    # Broad AppProject for platform components
│   │   ├── workloads-appset.yaml    # List generator -> dev/qa/staging
│   │   └── workloads-project.yaml   # Narrow AppProject for app workloads
│   └── prod/                        # Placeholder (not implemented)
│
├── clusters/
│   ├── nonprod/
│   │   ├── platform/                # One folder per cluster-wide component (auto-discovered)
│   │   │   ├── istio/
│   │   │   ├── kube-prometheus-stack/
│   │   │   └── namespace-policies/  # ResourceQuota/LimitRange/RBAC per workload namespace
│   │   │       ├── base/
│   │   │       └── overlays/{dev,qa,staging}/
│   │   └── workloads/                # Developer-owned app manifests
│   │       ├── base/microservice1/
│   │       └── overlays/{dev,qa,staging}/
│   └── prod/                        # Placeholder (not implemented)
│
├── local/kind/cluster.yaml           # Kind cluster config for local development
└── .github/CODEOWNERS                # Enforces the ownership boundary below
```

## Ownership boundary

Developers are only meant to touch `clusters/<env>/workloads/` (app manifests/overlays). Everything else — `bootstrap/`, `clusters/<env>/platform/`, `terraform/` — is admin-only, enforced via `.github/CODEOWNERS`.

Namespace-scoped guardrails (`ResourceQuota`/`LimitRange`/`Role`/`RoleBinding`) live under `platform/namespace-policies/`, not under `workloads/` — putting them in the dev-writable tree would let a workload change loosen its own constraints.

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
kubectl kustomize --enable-helm clusters/nonprod/platform/istio

# Render a platform Helm release locally for review
helm template <release> <chart> -f clusters/nonprod/platform/<component>/values.yaml
```

## Adding things

- **New platform component**: add a new directory under `clusters/nonprod/platform/` — auto-discovered by `platform-appset.yaml`'s git directory generator, no other changes needed.
- **New workload environment** (beyond dev/qa/staging): update the `list` generator in `bootstrap/nonprod/workloads-appset.yaml` *and* add a matching `clusters/nonprod/workloads/overlays/<newenv>/`.
- **New workload**: add a base under `clusters/nonprod/workloads/base/<name>/` and reference it from each overlay that should run it.

## Production readiness (roadmap, not yet implemented)

`bootstrap/prod/` and `clusters/prod/` are empty placeholders. Before any production workload runs through this setup, plan for:

1. **Manual sync for production** — disable `syncPolicy.automated` for prod Applications; require pipeline- or human-mediated approval to sync.
2. **RBAC + SSO/OIDC** — authenticate every access to the production ArgoCD instance (Dex/OIDC), no shared admin credentials, and scope `AppProject` roles per team.
3. **Secrets out of Git** — the production cluster's credentials must be injected via Terraform/secret manager at bootstrap time, never committed.
4. **Audit logging** — ship ArgoCD audit logs (syncs, logins, config changes) to a central SIEM.
5. **Monitoring & alerting** — alert on `argocd_app_sync_status`, `argocd_app_health_status`, and `argocd_app_repo_connection_status` via the ArgoCD Prometheus metrics endpoint.
6. **Backup & DR** — back up the `argocd` namespace (e.g. with Velero) before any major change, stored in a separate region/account, with a documented restore runbook.
7. **Prune protection** — annotate critical resources with `argocd.argoproj.io/sync-options: Prune=false` (or `PrunePropagationPolicy=foreground/orphan`) so they're never deleted automatically.
8. **Folder-based promotion** — promote changes `dev → qa → staging → prod` via PRs that copy manifests between environment folders, with CI validation at each stage and manual approval required for the `prod` PR.
