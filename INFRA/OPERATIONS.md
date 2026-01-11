# Operations Runbook

This runbook documents every command required by the README to provision clusters, install ArgoCD, deploy workloads, run tests, and clean up. Run all commands from the repository root (`/home/<user>/kubernetes/2526-ex-DemirEvren`).

> **Secrets**: export and keep the following out of Git — `GITHUB_USERNAME`, `GITHUB_TOKEN`, `POSTGRES_PASSWORD`, `JWT_SECRET`.

---

## 0. Prerequisites (one time)

| Requirement | Details |
|-------------|---------|
| Tooling     | Docker, k3d ≥ 5.6, kubectl ≥ 1.28, kustomize ≥ 5.0, jq, curl. |
| Access      | GitHub PAT with `repo` + `packages:write`. |
| DNS         | Add `127.0.0.1 shelfware.local test.shelfware.local` to `/etc/hosts`. |

Create the shared Docker network once:

```bash
docker network create k3d-shared || true
```

---

## 1. Application Cluster (`shelfware-app`)

### 1.1 Create the cluster

```bash
k3d cluster create shelfware-app \
  --network k3d-shared \
  --servers 1 \
  --agents 2 \
  --port "80:80@loadbalancer" \
  --port "443:443@loadbalancer" \
  --k3s-arg "--disable=traefik@server:0"

kubectl config use-context k3d-shelfware-app
```

### 1.2 Install ArgoCD

```bash
kubectl apply -k INFRA/argocd

kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd
kubectl wait --for=condition=ready --timeout=300s pod -l app.kubernetes.io/name=argocd-application-controller -n argocd
```

Add repository credentials:

```bash
kubectl create secret generic private-repo-creds \
  -n argocd \
  --from-literal=type=git \
  --from-literal=url="https://github.com/PXL-Systems-Expert/2526-ex-DemirEvren.git" \
  --from-literal=username="$GITHUB_USERNAME" \
  --from-literal=password="$GITHUB_TOKEN"

kubectl label secret private-repo-creds -n argocd \
  argocd.argoproj.io/secret-type=repository --overwrite
```

Create namespaces + secrets excluded from Git:

```bash
for ns in prod-shelfware test-shelfware; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic shelfware-secrets \
    -n "$ns" \
    --from-literal=database-url="postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/shelfware?schema=public" \
    --from-literal=postgres-password="$POSTGRES_PASSWORD" \
    --from-literal=jwt-secret="$JWT_SECRET"
done
```

### 1.3 Deploy workloads via ArgoCD

```bash
kubectl apply -f INFRA/argocd/applications/appcluster/

kubectl get applications -n argocd -w
kubectl get pods -A
```

Applications deployed (sync order): ingress-nginx, prometheus-operator, monitoring stack, KEDA, shelfware-test, shelfware-prod.

---

## 2. Load-Test Cluster (`shelfware-loadtest`)

### 2.1 Create the cluster

```bash
k3d cluster create shelfware-loadtest \
  --network k3d-shared \
  --servers 1 \
  --agents 2 \
  --k3s-arg "--disable=traefik@server:0" \
  --no-lb

kubectl config use-context k3d-shelfware-loadtest
```

### 2.2 Install ArgoCD + credentials

```bash
kubectl apply -k INFRA/argocd

kubectl create secret generic repo-creds \
  -n argocd \
  --from-literal=type=git \
  --from-literal=url="https://github.com/PXL-Systems-Expert/2526-ex-DemirEvren.git" \
  --from-literal=username="$GITHUB_USERNAME" \
  --from-literal=password="$GITHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label secret repo-creds -n argocd \
  argocd.argoproj.io/secret-type=repository --overwrite
```

### 2.3 Deploy Locust

```bash
kubectl apply -f INFRA/argocd/applications/loadtest/root-app.yaml -n argocd

kubectl get applications -n argocd
kubectl get pods -n locust
```

This syncs `INFRA/kustomize/locust/overlays/loadtest` (namespace, ConfigMap, master/worker Deployments, Services).

---

## 3. Verification & Testing

### 3.1 Ingress smoke tests

```bash
kubectl get ingress -A

curl -H "Host: shelfware.local" http://127.0.0.1/
curl -H "Host: test.shelfware.local" http://127.0.0.1/

curl -H "Host: shelfware.local" http://127.0.0.1/health
curl -H "Host: shelfware.local" http://127.0.0.1/ready
```

### 3.2 Backend/API checks

```bash
for host in shelfware.local test.shelfware.local; do
  curl -H "Host: $host" http://127.0.0.1/api/projects | jq 'length'
  curl -H "Host: $host" http://127.0.0.1/api/projects \
    -H 'Content-Type: application/json' \
    -d '{"name":"Demo","description":"Smoke"}'
done
```

### 3.3 Monitoring stack

```bash
./scripts/port-forwards.sh   # exposes Prometheus, Grafana, Locust
```

| Service   | URL                  | Notes |
|-----------|----------------------|-------|
| Grafana   | http://localhost:3000 | Login `admin/prom-operator`, open "Four Golden Signals" dashboard. |
| Prometheus| http://localhost:9090 | Confirm scrape targets + query rates. |
| Locust    | http://localhost:8089 | Launch UI-driven load tests. |

### 3.4 Headless Locust run

```bash
locust --headless --host http://shelfware.local -u 100 -r 10 --run-time 10m

kubectl get hpa -A
kubectl top pods -A
```

### 3.5 Cleanup

```bash
k3d cluster delete shelfware-app
k3d cluster delete shelfware-loadtest

# Optional when finished completely
docker network rm k3d-shared
```

---

## 4. Troubleshooting Cheatsheet

| Symptom | Command |
|---------|---------|
| Pods Pending | `kubectl describe pod <name>` to inspect taints/PVC events. |
| Image pull failures | `kubectl get events -A --field-selector involvedObject.name=<pod>` |
| ArgoCD app stuck | `kubectl logs deployment/argocd-repo-server -n argocd` |
| Missing metrics | `kubectl get servicemonitor -A -o wide` to validate selectors. |

Capture full state before asking for help: `kubectl get all -A`.
