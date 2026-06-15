# gitops-aks-platform
GitOps-driven AKS platform using Terraform, ArgoCD, Istio, Envoy Gateway, Karpenter, Kind, and Floci. A reference implementation of modern platform engineering practices with local-first development and enterprise-grade Kubernetes operations.


# GitOps with ArgoCD – Production Readiness Checklist

This repository implements a GitOps workflow using ArgoCD, with **separate ArgoCD instances** for non‑production (dev, QA, staging) and production environments. Terraform is used **only to bootstrap** each ArgoCD instance (install the Helm chart and create the initial root `Application`). After bootstrap, all configuration lives in Git and is managed by ArgoCD itself.

> **⚠️ Important**  
> The current setup provides a solid foundation, but **production‑grade safety requires additional hardening**. This document lists the mandatory security controls and operational practices before you trust production workloads to this system.

---

## 🔒 Non‑negotiable Production Requirements

### 1. Manual Sync and Approval for Production

**Do not enable automatic sync for production.** Any change to production must go through a manual or pipeline‑mediated approval.

✅ **How to implement**  
In the `ApplicationSet` (or `Application`) for production, use:

```yaml
syncPolicy:
  automated: {}        # Disable prune/selfHeal automation
  syncOptions:
    - ApplyOutOfSyncOnly=true


And optionally restrict sync windows:

```yaml
syncWindows:
  - kind: deny
    schedule: "0 0 * * *"   # block all syncs except explicit allow
    duration: 23h59m
    manualSync: true
```

## 2. RBAC + SSO / OIDC
Every access to the production ArgoCD must be authenticated and authorised. No shared admin credentials.

### ✅ How to implement

- Configure dex (or OIDC directly) in argocd-cm:
```yaml
data:
  url: https://argocd.prod.example.com
  dex.config: |
    connectors:
      - type: oidc
        name: YourIdP
        config:
          issuer: https://your-org.okta.com
          clientID: $dex.oidc.clientID
          clientSecret: $dex.oidc.clientSecret
```

- Define AppProject roles to restrict who can sync production applications:

```yaml
roles:
  - name: release-manager
    policies:
      - p, proj:prod:release-manager, applications, sync, *, allow
    groups:
      - your-org:prod-approvers
```

## 3. Secure Storage of Production Cluster Credentials
The kubeconfig or API token for the production cluster must never be stored in Git.

### ✅ How to implement

Create the production cluster secret only via Terraform during bootstrap:

```hcl
resource "kubernetes_secret" "prod_cluster" {
  metadata {
    name      = "prod-cluster-secret"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
    }
  }
  data = {
    name   = "prod-cluster"
    server = var.prod_cluster_server
    config = base64encode(jsonencode({
      bearerToken = var.prod_cluster_token
      tlsClientConfig = {
        caData = var.prod_cluster_ca
      }
    }))
  }
  type = "Opaque"
}
```

- Inject the token via a secrets management tool (Vault, AWS Secrets Manager) – never hardcode.

## 4. Audit Logging & SIEM Integration
All operations (syncs, logins, configuration changes) must be logged and shipped to a central SIEM.

### ✅ How to implement

- Enable audit logs in argocd-cm:
```yaml
data:
  audit.log.path: /var/log/argocd/audit.log
  audit.log.format: json
```
Deploy a log collector (Fluentd, Vector) to forward logs to your SIEM (Splunk, Datadog, Elastic).

## 5. Monitoring & Alerting
You must know immediately when a production sync fails, an application becomes degraded, or the ArgoCD control plane is unhealthy.

### ✅ How to implement

- Use the ArgoCD Prometheus metrics endpoint.

- Create alerts for:
    
    - `argocd_app_sync_status{status!="Synced"}`

    - `argocd_app_health_status{status!="Healthy"}`

    - `argocd_app_repo_connection_status{status!="Successful"}`

- Send notifications to PagerDuty, Opsgenie, or a dedicated Slack channel.


## 6. Backup & Disaster Recovery
Losing the ArgoCD `argocd` namespace means losing your deployment configuration. You must have a recoverable backup.

### ✅ How to implement

- Use Velero to back up the `argocd` namespace daily and before any major change.

- Store backups in a different cloud region / account.

- Document a runbook to restore ArgoCD from backup, including the production cluster secret.

## 7. Protect Critical Resources from Deletion
Some resources (e.g., a production database, a namespace with resource quotas) must never be pruned automatically.

### ✅ How to implement

- Annotate the Kubernetes manifests in Git:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: Prune=false
```

- Also consider `PrunePropagationPolicy=foreground` or `orphan` for certain resources.

### 8. Promotion Pipeline (Folder‑Based, No Gitflow)

Changes must flow through environment folders **sequentially**, with automated tests between each stage. **Do not use Git branches** – use directories.

✅ **How to implement (folder‑based promotion)**

Your Git repository already has environment folders:

```
clusters/
├── dev/
├── qa/
├── staging/
└── prod/
```


**Promotion flow:**

1. Developer commits a change to `clusters/dev/` (CI runs tests against dev).
2. After dev tests pass, the change is **copied** (not merged) to `clusters/qa/` (via automated script or manual PR).
3. QA tests pass → copy to `clusters/staging/`.
4. Staging tests pass → create a PR that copies the change to `clusters/prod/`.
5. PR requires manual approval (from release manager / security).
6. After approval, the PR is merged – production ArgoCD detects the change (no auto‑sync, manual sync required).

**Automation with CI (no Gitflow):**

Use a simple CI pipeline (GitHub Actions, GitLab CI) that:
- Watches for changes in `clusters/dev/`
- Runs tests against the dev cluster
- If tests pass, automatically creates a PR that mirrors the change to `clusters/qa/`
- Similar automation for `qa → staging`
- For `staging → prod`, the CI creates a PR but waits for manual approval

**Why this is better than Gitflow:**
- No long‑lived branches, no merge hell.
- The `main` branch (or `trunk`) always reflects the exact state of `clusters/prod/`.
- Every environment’s configuration is stored in a folder, easy to compare.
- Promotions are explicit and auditable via PRs.

**Example GitHub Actions workflow (simplified):**

```yaml
name: Promote to QA
on:
  push:
    paths:
      - 'clusters/dev/**'
jobs:
  test-dev:
    runs-on: ubuntu-latest
    steps:
      - run: kubectl apply --dry-run=server -k clusters/dev
  promote-to-qa:
    needs: test-dev
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: |
          rsync -av clusters/dev/ clusters/qa/
          git config user.name "CI Bot"
          git commit -am "Promote dev to qa"
          git push origin main
```

**Important:** The production ArgoCD still uses manual sync (no automation). The PR that updates clusters/prod/ must be approved by a human.


## 🔐 CODEOWNERS – Mandatory Approval for Production Changes

To prevent unauthorised modifications to critical environment folders, you **must** define a `CODEOWNERS` file in your repository. This file specifies which individuals or teams must approve pull requests that change specific paths.

### Recommended CODEOWNERS rules (folder‑based)

```text
# Root – platform team owns everything
* @your-org/platform-engineers

# Development – any developer can approve
/clusters/dev/     @your-org/dev-team

# QA – QA lead approval required
/clusters/qa/      @your-org/qa-lead

# Staging – staging approvers required
/clusters/staging/ @your-org/staging-approvers

# PRODUCTION – only release managers can approve
/clusters/prod/    @your-org/prod-approvers

# Shared components – platform team only
/components/       @your-org/platform-engineers
```

## Folder structure

```text
gitops-aks-platform/
│
├── bootstrap/
│   ├── nonprod/                               # Bootstraps the non-production ArgoCD
│   │   ├── appsets/
│   │   │   ├── env-appset.yaml                # Generates environment applications
│   │   │   └── infra-appset.yaml              # Generates infrastructure applications
│   │   │
│   │   ├── projects/
│   │   │   ├── base/
│   │   │   │   ├── kustomization.yaml
│   │   │   │   └── project.yaml              # Base AppProject definition
│   │   │   │
│   │   │   └── overlays/
│   │   │       └── dev/
│   │   │           ├── kustomization.yaml
│   │   │           └── patch.yaml            # Environment-specific project settings
│   │   │
│   │   └── kustomization.yaml                # Root bootstrap entrypoint
│   │
│   └── prod/
│       └── ...
│
├── clusters/                                  # Actual workload & infrastructure manifests
│   ├── nonprod/                               # Referenced by nonprod-appset.yaml
│   │   ├── infrastructure/                    # Cluster‑wide components (installed once)
│   │   │   ├── istio/                         # Istio control plane (istio-system ns)
│   │   │   ├── cert-manager/                  # Cluster cert manager
│   │   │   └── observability/                 # Prometheus, Grafana, Loki (single instance)
│   │   └── environments/                      # Per‑namespace workloads
│   │       ├── dev/                           # Dev namespace manifests
│   │       ├── qa/                            # QA namespace manifests
│   │       └── staging/                       # Staging namespace manifests
│   └── prod/                                  # Referenced by prod-appset.yaml
│       ├── infrastructure/                    # (Optional) Prod‑specific cluster components
│       └── environments/
│           └── prod/                          # Prod namespace manifests
│
├── shared/                                    # Reusable Kustomize bases
│   └── kustomize-bases/
│       ├── your-app/                          # Base Deployment, Service, etc.
│       └── istio/                             # Base patches (if needed)
│
└── terraform/                                 # Infrastructure as Code (separate from GitOps)
    ├── modules/
    │   └── argocd-bootstrap/                  # Reusable Terraform module
    │       ├── main.tf                        # Installs ArgoCD + creates root Application
    │       ├── variables.tf
    │       ├── outputs.tf
    │       └── versions.tf                    # Required providers and Terraform version
    ├── nonprod/                               # Bootstraps non‑prod cluster
    │   ├── main.tf                            # Calls module with bootstrap_path = "bootstrap/nonprod"
    │   ├── terraform.tfvars                   # Values for nonprod (cluster_name = "nonprod", etc.)
    │   └── backend.tf                         # (Optional) Remote state config
    └── prod/                                  # Bootstraps prod cluster
        ├── main.tf                            # Calls module with bootstrap_path = "bootstrap/prod"
        ├── terraform.tfvars                   # Values for prod (cluster_name = "prod", manual sync)
        └── backend.tf                         # (Optional) Remote state, ideally separate
```