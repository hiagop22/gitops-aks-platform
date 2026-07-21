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

The components are installed in dependency order:

```text
istio-base
    ↓
istiod
    ↓
istio-ingress
```

Namespaces join the mesh through:

```yaml
metadata:
  labels:
    istio-injection: enabled
```

This label is managed centrally from `platform/namespace-policies`, not by application manifests.

The `istio-ingress` namespace should normally **not** have sidecar injection enabled because the ingress gateway is already an Envoy proxy and does not require an additional sidecar.

---

# ArgoCD sync waves

ArgoCD sync waves define the relative installation order of resources that are synchronized together.

The platform uses the following order:

| Sync wave | Component | Namespace |
|---:|---|---|
| `-2` | `istio-base` | `istio-system` |
| `-1` | `istiod` | `istio-system` |
| `0` | `istio-ingress` | `istio-ingress` |
| `1` | Shared `Gateway` resources | `istio-ingress` |
| `2` | Application `VirtualService` resources | Workload namespace |

Example platform Application values:

```yaml
# istio-base
destinationNamespace: istio-system
syncWave: "-2"
```

```yaml
# istiod
destinationNamespace: istio-system
syncWave: "-1"
```

```yaml
# istio-ingress
destinationNamespace: istio-ingress
syncWave: "0"
```

Negative waves are valid. There is no requirement for workload routes to use wave `0`; the values only define relative ordering.

> Important: sync waves order resources within the same ArgoCD synchronization operation. They do not create a permanent runtime dependency between independently synchronized ArgoCD Applications.


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

The injected Envoy sidecar receives configuration from `istiod` and handles service-mesh traffic for the application container.

---

# Istio ingress model

Ingress traffic is handled by three separate layers:

```text
Internet
   │
   ▼
istio-ingress
Envoy Deployment + Kubernetes Service
   │
   ▼
Gateway
Accepted ports, protocols, and hosts
   │
   ▼
VirtualService
Routing rules and destination Services
   │
   ▼
Kubernetes Service
   │
   ▼
Application Pods
```

## `istio-ingress`

`istio-ingress` is the actual runtime infrastructure that receives external traffic.

It consists primarily of:

- A Kubernetes `Deployment` running Envoy gateway pods
- A Kubernetes `Service` exposing those pods
- A `LoadBalancer` Service on AKS
- A `NodePort` or locally mapped Service when running with Kind

Without this component, there is no ingress Envoy proxy available to receive traffic from outside the cluster.

Example runtime resources:

```text
istio-ingressgateway Deployment
istio-ingressgateway LoadBalancer Service
```

On AKS, the `LoadBalancer` Service receives an external IP from Azure.

---

## `Gateway`

An Istio `Gateway` tells the ingress Envoy proxy which traffic it may accept.

It defines:

- Listening ports
- Protocols
- Hostnames
- TLS configuration

Example:

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: shared-gateway
  namespace: istio-ingress
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - app.example.com
```

This configuration means:

```text
Accept HTTP traffic
on port 80
for app.example.com
```

The `Gateway` defines the entry point but does not define the destination application.

Shared `Gateway` resources are platform-managed and should normally be stored under:

```text
clusters/<env>/platform/istio-ingress/
```

---

## `VirtualService`

A `VirtualService` defines how traffic accepted by a `Gateway` is routed to Kubernetes Services.

It may match requests by:

- Host
- URI path
- HTTP headers
- HTTP method
- Query parameters
- Traffic percentage

Example:

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: backend
  namespace: dev
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  hosts:
    - app.example.com
  gateways:
    - istio-ingress/shared-gateway
  http:
    - match:
        - uri:
            prefix: /api
      route:
        - destination:
            host: backend.dev.svc.cluster.local
            port:
              number: 8080
```

This configuration means:

```text
Requests to:

http://app.example.com/api

are routed to:

backend.dev.svc.cluster.local:8080
```

Application-specific `VirtualService` resources may be stored under:

```text
clusters/<env>/workloads/overlays/<environment>/
```

The referenced gateway uses the format:

```text
<gateway-namespace>/<gateway-name>
```

For example:

```yaml
gateways:
  - istio-ingress/shared-gateway
```

---

# Complete ingress request flow

Suppose a client sends:

```text
http://app.example.com/api/users
```

The request follows this path:

```text
1. Azure Load Balancer receives the external request.
2. The Kubernetes LoadBalancer Service forwards it to an ingress Envoy pod.
3. The Gateway checks:
   - Was the request received on an allowed port?
   - Does the Host header match app.example.com?
4. The VirtualService checks:
   - Does the request path start with /api?
5. Envoy routes the request to:
   backend.dev.svc.cluster.local:8080
6. The Kubernetes Service selects one of the backend Pods.
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