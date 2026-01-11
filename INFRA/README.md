# Infrastructure Overview

This README summarizes the tooling, architecture, and test approach for the Shelfware deployment described in `INFRA/`. Run every command from the repository root unless noted otherwise.

## Tooling & Platforms

| Tool | Purpose |
|------|---------|
| Docker + k3d | Provision two local Kubernetes clusters (`shelfware-app`, `shelfware-loadtest`) that share a Docker network. |
| kubectl + kustomize | Apply manifests, manage resources, and render the Kustomize overlays for `test`, `prod`, and `loadtest`. |
| ArgoCD | GitOps controller installed declaratively via `INFRA/argocd`, syncing all workloads. |
| GitHub Actions | Builds container images on tags and updates overlay image references automatically. |
| Prometheus + Grafana (kube-prometheus-stack) | Monitoring stack deployed through manifests under `INFRA/monitoring`. |
| KEDA | Event-driven autoscaling for the frontend (prod overlay). |
| Locust | Load testing suite running on the `loadtest` cluster against the prod ingress endpoint. |

### Required Secrets / Environment

Export (but never commit) the following before running the docs:

```
export GITHUB_USERNAME="DemirEvren"
export GITHUB_TOKEN="<PAT with repo+packages:write>"
export POSTGRES_PASSWORD="<db password>"
export JWT_SECRET="<jwt secret>"
```

Add `127.0.0.1 shelfware.local test.shelfware.local` to `/etc/hosts` so ingress hosts resolve.

## Architecture Overview

Top-level structure:

```
INFRA/
├── argocd/               # Namespace + install + Applications (root, prod, test, infra)
├── ingress-nginx/        # Ingress controller manifests
├── keda/                 # Declarative KEDA install
├── kustomize/
│   ├── shelfware/
│   │   ├── base/         # Backend, frontend, PostgreSQL, ServiceMonitor
│   │   └── overlays/
│   │       ├── test/     # Fixed replicas, test ingress, labels
│   │       └── prod/     # HPA/KEDA, prod ingress, secrets
│   └── locust/           # Base + loadtest overlay for Locust
├── monitoring/           # Prometheus operator CRDs, kube-prom stack manifests, dashboards
├── MONITORING.md         # Stack-specific instructions
└── OPERATIONS.md         # Runbook with exact commands
```

**Cluster Roles**

- `shelfware-app`: Runs ingress-nginx, Prometheus operator, kube-prometheus-stack, KEDA, and the Shelfware app namespaces (`test-shelfware`, `prod-shelfware`). ArgoCD root app (`INFRA/argocd/applications/appcluster/root-app.yaml`) recursively applies infra + env apps with sync waves.
- `shelfware-loadtest`: Runs a minimal ArgoCD plus the Locust overlay (`INFRA/kustomize/locust/overlays/loadtest`). Locust reaches the Shelfware ingress via `http://shelfware.local`.

**Kustomize Highlights**

- Base manifests keep shared definitions (Deployments, Services, StatefulSet, ConfigMaps, ServiceMonitor).
- Overlays inject environment-specific ConfigMap patches, ingress hosts, replica policies, and image overrides.
- Prod overlay adds `hpa.yaml` and `keda-scaledobject.yaml` for autoscaling on CPU + Prometheus request rate.

**GitOps Flow**

1. GitHub tag (`TEST_*` or `PROD_*`) pushes via workflow.
2. Workflow builds backend/frontend images (`ghcr.io/demirevren/shelfware-*:<tag>`), updates the matching overlay `kustomization.yaml`, commits the change, and pushes to `main`.
3. ArgoCD auto-syncs the overlay, rolling out the new tag to the proper namespace.

## End-to-End Testing

All command-level detail lives in `INFRA/OPERATIONS.md`. The sections below summarize the validation sequence once both clusters are online and ArgoCD has synced.

### 1. Application Reachability

1. `kubectl get ingress -A` on `k3d-shelfware-app` to confirm hosts `shelfware.local` and `test.shelfware.local` resolve to the ingress controller.
2. `curl -H "Host: shelfware.local" http://127.0.0.1/` and `/api/projects` for prod; repeat with `test.shelfware.local` for test.
3. Check health probes: `/health`, `/ready` return HTTP 200.

### 2. Database & Secrets

Secrets (`postgres-secret`, `shelfware-secrets`) are created manually per namespace following `OPERATIONS.md`. Validate the StatefulSet:

```
kubectl get statefulsets -n prod-shelfware
kubectl describe pvc postgres-storage-postgres-0 -n prod-shelfware
```

### 3. Monitoring Stack

1. Run `./scripts/port-forwards.sh` option 1 to expose Grafana (3000) and Prometheus (9090).
2. Log into Grafana (`admin/prom-operator`) and open the "Backend API Four Golden Signals" dashboard (auto-provisioned from `INFRA/monitoring/dashboards`).
3. Ensure ServiceMonitor picks up the backend: `kubectl get servicemonitors.monitoring.coreos.com -n prod-shelfware backend -o yaml`.

### 4. Autoscaling Checks

- For CPU-based HPA: `kubectl get hpa -n prod-shelfware frontend-hpa`. Generate synthetic load (e.g., `hey` or Locust) and watch `kubectl describe hpa frontend-hpa`.
- For KEDA: ensure the ScaledObject is ready (`kubectl get scaledobjects.keda.sh -n prod-shelfware`). Prometheus queries feed the autoscaling decisions.

### 5. Locust Load Tests

On the `k3d-shelfware-loadtest` context:

1. Confirm pods: `kubectl get pods -n locust`.
2. Launch the UI: `kubectl port-forward svc/locust-master -n locust 8089:8089` and start a run with host `http://shelfware.local` (Host header `shelfware.local`).
3. For CI-style validation, use headless mode:

```
locust --headless --host http://shelfware.local -u 100 -r 10 --run-time 10m
```

Monitor prod metrics during the run (Grafana dashboard, Prometheus queries, ArgoCD sync status).

### 6. Cleanup

Run the cleanup block in `INFRA/OPERATIONS.md` (`k3d cluster delete ...` and optional `docker network rm k3d-shared`).

---

For the exact shell commands that realize everything described above, follow `INFRA/OPERATIONS.md`. This README focuses on the *what* and *why* so reviewers can understand the approach before running the procedures.
