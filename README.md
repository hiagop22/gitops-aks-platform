# gitops-aks-platform

GitOps-driven AKS/Kubernetes platform built with Terraform, ArgoCD, Helm, Kustomize, and Istio.

Terraform bootstraps a single ArgoCD instance per environment. From that point onward, ArgoCD owns the desired state of the cluster and continuously reconciles everything from Git.

Currently only the **`nonprod`** environment is implemented. `bootstrap/prod/` and `clusters/prod/` exist as placeholders for future production deployment.

---

# Architecture

## Layer 1 — Terraform (`terraform/`)

Terraform is responsible only for bootstrapping GitOps by:

- Creating the `argocd` namespace
- Installing the ArgoCD Helm chart
- Creating a single root `Application` pointing to `bootstrap/<environment>`

Terraform does **not** manage applications after ArgoCD has been installed.

---

## Layer 2 — GitOps (`bootstrap/`, `clusters/`)

Once the root `Application` exists, ArgoCD becomes the source of truth for the cluster.

The bootstrap layer contains:

- **`platform-appset.yaml`**
  - Uses a **Git directory generator**
  - Automatically discovers every directory under:
    ```
    clusters/<env>/platform/*
    ```
  - Every directory becomes an independent ArgoCD Application.

- **`workloads-appset.yaml`**
  - Uses a **List generator**
  - Deploys workload overlays for:
    - `dev`
    - `qa`
    - `staging`

- **AppProjects**
  - `platform-project`
    - Cluster-wide permissions
    - CRDs
    - Namespaces
    - Infrastructure components
  - `workloads-project`
    - Namespace-scoped only
    - Restricted to workload namespaces
    - Prevents developers from modifying cluster infrastructure

---

# Repository structure

```text
gitops-aks-platform/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── providers.tf
│   ├── versions.tf
│   ├── environment/
│   │   └── nonprod/
│   │       ├── backend.tf
│   │       └── terraform.tfvars
│   └── modules/
│       └── argocd/
│           ├── argocd.tf
│           ├── applications.tf
│           ├── variables.tf
│           └── versions.tf
│
├── bootstrap/
│   ├── nonprod/
│   │   ├── platform-appset.yaml
│   │   ├── platform-project.yaml
│   │   ├── workloads-appset.yaml
│   │   └── workloads-project.yaml
│   └── prod/
│
├── clusters/
│   ├── nonprod/
│   │   ├── platform/
│   │   │   ├── istio-base/
│   │   │   ├── istiod/
│   │   │   ├── istio-ingress/
│   │   │   ├── kube-prometheus-stack/
│   │   │   └── namespace-policies/
│   │   │       ├── base/
│   │   │       └── overlays/
│   │   │           ├── dev/
│   │   │           ├── qa/
│   │   │           └── staging/
│   │   │
│   │   └── workloads/
│   │       ├── base/
│   │       └── overlays/
│   │           ├── dev/
│   │           ├── qa/
│   │           └── staging/
│   └── prod/
│
├── local/
│   └── kind/
│       └── cluster.yaml
│
└── .github/
    └── CODEOWNERS
```

---

# Ownership boundary

Platform engineers own:

- Terraform
- Bootstrap configuration
- Platform components
- Namespaces
- Istio
- Observability
- RBAC
- ResourceQuota
- LimitRange

Application developers own only:

```text
clusters/<env>/workloads/
```

Everything else is administrator-managed and protected through
`.github/CODEOWNERS`.

Namespace guardrails such as:

- ResourceQuota
- LimitRange
- Role
- RoleBinding

are intentionally stored under:

```text
clusters/<env>/platform/namespace-policies/
```

instead of the workload tree so that application teams cannot relax their own constraints.

---

# Istio architecture

Istio is deployed as **three independent platform components**.

| Component | Purpose |
|-----------|---------|
| `istio-base` | CRDs and cluster-scoped resources |
| `istiod` | Service mesh control plane |
| `istio-ingress` | Ingress Gateway |

Namespaces join the mesh through:

```yaml
metadata:
  labels:
    istio-injection: enabled
```

This label is managed centrally from `platform/namespace-policies`, not by application manifests.

---

# Sidecar injection

```text
Developer
      │
      ▼
Deployment
      │
      ▼
Namespace
(istio-injection=enabled)
      │
      ▼
Mutating Admission Webhook
      │
      ▼
Pod
├── Application
└── Envoy Sidecar
        │
        ▼
      istiod
```

---

# Envoy configuration model

Istio distributes configuration to Envoy proxies using the xDS APIs.

| xDS | Purpose | Inspect with |
|------|----------|--------------|
| LDS | Listeners | `istioctl proxy-config listeners` |
| RDS | HTTP Routes | `istioctl proxy-config routes` |
| CDS | Upstream Clusters | `istioctl proxy-config clusters` |
| EDS | Service Endpoints | `istioctl proxy-config endpoints` |

When debugging service mesh traffic, inspect the generated Envoy configuration before assuming Kubernetes networking is the issue.

---

# Common commands

## Terraform

```bash
terraform init

terraform plan \
  -var-file=environment/nonprod/terraform.tfvars

terraform apply \
  -var-file=environment/nonprod/terraform.tfvars
```

## Local Kind cluster

```bash
kind create cluster --config local/kind/cluster.yaml
```

## Validate workloads

```bash
kubectl apply \
  --dry-run=server \
  -k clusters/nonprod/workloads/overlays/dev
```

## Render platform components

```bash
kubectl kustomize \
  --enable-helm \
  clusters/nonprod/platform/istiod
```

or

```bash
helm template <release> <chart> \
  -f clusters/nonprod/platform/<component>/values.yaml
```

## Verify sidecar injection

```bash
kubectl get pod <pod> \
  -o jsonpath='{.spec.containers[*].name}'
```

## Check namespace labels

```bash
kubectl get ns --show-labels
```

## Restart workloads after enabling injection

```bash
kubectl rollout restart deployment <deployment> \
  -n <namespace>
```

## Verify proxies connected to istiod

```bash
istioctl proxy-status
```

## Inspect Envoy configuration

```bash
istioctl proxy-config listeners <pod> -n <namespace>

istioctl proxy-config routes <pod> -n <namespace>

istioctl proxy-config clusters <pod> -n <namespace>

istioctl proxy-config endpoints <pod> -n <namespace>
```

## Validate Istio configuration

```bash
istioctl analyze
```

---

# Adding new components

## Add a new platform component

Create a new directory under:

```text
clusters/nonprod/platform/
```

The Git directory generator automatically creates a new ArgoCD Application.

No additional configuration is required.

---

## Add a new workload

Create a base under:

```text
clusters/nonprod/workloads/base/<application>/
```

Then reference it from the desired environment overlays.

---

## Add a new environment

1. Update the List generator inside:

```text
bootstrap/nonprod/workloads-appset.yaml
```

2. Create:

```text
clusters/nonprod/workloads/overlays/<environment>/
```

---

# Troubleshooting checklist

1. Verify `istiod` is running.
2. Verify the namespace has `istio-injection=enabled`.
3. Restart Deployments after labeling namespaces.
4. Confirm Pods contain `istio-proxy`.
5. Check `istioctl proxy-status`.
6. Inspect listeners, routes, clusters, and endpoints.
7. Run `istioctl analyze`.

---

# Learning roadmap

1. Sidecar injection
2. Kubernetes Services
3. Service discovery
4. VirtualService
5. DestinationRule
6. Ingress Gateway
7. mTLS
8. AuthorizationPolicy
9. Kubernetes Gateway API
10. Ambient mode

---

# Production roadmap

The `prod` environment is intentionally left as a placeholder. Before deploying production workloads, the following improvements should be implemented.

1. **Manual synchronization**
   - Disable automatic sync for production Applications.
   - Require pipeline or human approval before deployments.

2. **SSO / OIDC**
   - Integrate ArgoCD with an identity provider.
   - Remove shared administrator credentials.
   - Define AppProject roles per team.

3. **Secrets outside Git**
   - Inject production credentials during Terraform bootstrap.
   - Use a secrets manager instead of storing secrets in Git.

4. **Audit logging**
   - Export ArgoCD audit logs to a centralized SIEM.

5. **Monitoring and alerting**
   - Monitor:
     - `argocd_app_sync_status`
     - `argocd_app_health_status`
     - `argocd_app_repo_connection_status`

6. **Backup and disaster recovery**
   - Back up the `argocd` namespace (e.g. using Velero).
   - Store backups in a separate region/account.
   - Maintain a documented restore procedure.

7. **Prune protection**
   - Protect critical resources using:

```yaml
argocd.argoproj.io/sync-options: Prune=false
```

or appropriate prune propagation policies.

8. **Git-based promotion**
   - Promote changes:

```
dev → qa → staging → prod
```

through Pull Requests with automated validation and manual approval before production.

9. **Gateway API migration**
   - Replace the Istio Ingress Gateway with the Kubernetes Gateway API when appropriate.