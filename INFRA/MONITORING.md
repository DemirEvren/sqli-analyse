# Monitoring Setup & Extras 3 & 4 Implementation

## Overview

This document describes the automated monitoring setup for Shelfware using Prometheus, Grafana, and KEDA.

## Extra 3: Prometheus/Grafana (3 points) ✅

### Automated Deployment

The complete monitoring stack is deployed declaratively via IaC using the `kube-prometheus-stack` Helm chart.

**Components:**
- **Prometheus**: Metrics collection and querying (v2.54.1)
- **Grafana**: Dashboard and visualization 
- **Prometheus Operator**: Manages Prometheus and AlertManager custom resources
- **Node Exporter**: Host-level metrics
- **Kube-State-Metrics**: Kubernetes object metrics

### Sync Wave Order

The deployment uses sync-wave priority to ensure CRDs are available before resources that use them:

```
Wave -3: prometheus-operator Application
  ├─ Installs 5 CRDs:
  │  ├─ PodMonitor (podmonitors.monitoring.coreos.com)
  │  ├─ Probe (probes.monitoring.coreos.com)  
  │  ├─ Prometheus (prometheuses.monitoring.coreos.com)
  │  ├─ PrometheusRule (prometheusrules.monitoring.coreos.com)
  │  └─ ServiceMonitor (servicemonitors.monitoring.coreos.com)
  └─ Prometheus operator binary

Wave -1: monitoring-stack Application
  ├─ Uses CRDs to create:
  │  ├─ Prometheus StatefulSet
  │  ├─ Grafana Deployment
  │  ├─ ServiceMonitors for all components
  │  └─ ConfigMaps for Grafana dashboard provisioning
  └─ Exposes services via cluster IPs
```

### Four Golden Signals Dashboard

A custom Grafana dashboard has been created that monitors the Backend API according to Google SRE standards:

**Location:** `/INFRA/monitoring/kustomize/grafana-dashboard.yaml`

**Dashboard Components:**

1. **Latency (P95/P99 Histograms)**
   - Query: `histogram_quantile(0.95/0.99, rate(http_request_duration_seconds_bucket[5m]))`
   - Displays percentile response times (not averages)
   - Alerts on > 500ms P99

2. **Traffic (Requests per Second by Method)**
   - Query: `sum(rate(http_requests_total[5m])) by (method)`
   - Splits traffic by GET vs POST requests
   - Shows total RPS and per-method breakdown

3. **Errors (5xx Response Rate %)**
   - Query: `sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))`
   - Displays percentage of failed requests
   - Alert threshold: > 1%

4. **Saturation (CPU & Memory Usage)**
   - CPU: `rate(container_cpu_usage_seconds_total[5m])`
   - Memory: `container_memory_usage_bytes / container_spec_memory_limit_bytes`
   - Shows pod utilization vs limits

### Auto-Import Configuration

The dashboard is automatically imported into Grafana on startup via:

1. **ConfigMap with Grafana Label**
   ```yaml
   metadata:
     labels:
       grafana_dashboard: "1"  # Triggers auto-import
   ```

2. **Grafana Provider Configuration**
   - Helm chart includes dashboard provider pointing to ConfigMaps with the label
   - No manual "Import" button needed

3. **Verification**
   - Dashboard appears in Grafana automatically after pod startup
   - Accessible at: `http://grafana:3000 → Dashboards → Four Golden Signals`

## Extra 4: Event-Driven Autoscaling (KEDA) (2 points) ✅

### KEDA Installation

KEDA is installed declaratively in `/INFRA/keda/keda-install.yaml` via ArgoCD wave -2.

### ScaledObject Configuration

Frontend pods scale based on incoming HTTP request rate:

**File:** `/INFRA/kustomize/shelfware/overlays/prod/keda-scaledobject.yaml`

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: frontend-scaler-prod
spec:
  scaleTargetRef:
    name: frontend
  minReplicaCount: 1
  maxReplicaCount: 3
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://monitoring-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090
      metricName: http_requests_per_second
      query: sum(rate(http_requests_total{namespace="prod-shelfware"}[2m])) / count(kube_pod_info{namespace="prod-shelfware",pod=~"frontend-.*"})
      threshold: "10"  # Scale up when > 10 requests/sec per pod
```

**Scaling Behavior:**
- **Metric:** Request rate from Prometheus (via http_requests_total)
- **Threshold:** 10 requests/second per pod
- **Min Replicas:** 1
- **Max Replicas:** 3
- **Scale-up:** When threshold exceeded, KEDA creates additional pods
- **Scale-down:** When traffic decreases, pods are gradually removed

### Why This Works Better Than HPA

Traditional HPA scales on CPU/Memory, which are **lagging indicators**:
- Request → CPU spike → Pod spawning → ~30s delay
- During spike, requests get throttled/timeout

KEDA scales on request rate, a **leading indicator**:
- Request rate increases → Pods spawn **immediately**
- No gap between request spike and capacity increase
- Backend stays responsive

### Demonstrating KEDA Scaling

To show KEDA in action for your presentation:

1. **Generate Load:**
   ```bash
   kubectl exec -it deployment/locust-master -n loadtest -- \
     locust -f locustfile.py -u 100 -r 10 --run-time 5m \
     --headless -H http://frontend.prod-shelfware.svc.cluster.local:80
   ```

2. **Watch Replicas Scale:**
   ```bash
   kubectl get hpa -n prod-shelfware -w
   # or
   kubectl get pods -n prod-shelfware -l app=frontend -w
   ```

3. **Monitor Request Rate in Grafana:**
   - Dashboard → Traffic panel
   - Watch RPS increase
   - Watch replicas increase **in parallel** (not after CPU spikes)

4. **Screenshot Evidence:**
   - Open Grafana dashboard
   - Start load test
   - After 2 minutes, take screenshot showing:
     - Traffic panel: RPS increasing
     - Saturation panel: CPU throttling NOT spiking
     - HPA status: Replicas scaling up
   - This proves KEDA scales **before** resource exhaustion

## Commit History

All fixes are committed and pushed to GitHub main branch:

1. **b720bfd**: Update locustfile.py: add get_projects task and fix BASE_URL to ingress IP
   - Problem: Locust was only testing 2 endpoints (root, health), missing backend API endpoint
   - Solution: Added `/api/projects` task with weight 5 for realistic backend load distribution
   - Also fixed BASE_URL from loadbalancer (172.18.0.7) to ingress IP (172.18.0.5) for metric capture

2. **b7894c5**: Fix Locust configmap: add get_projects task and update BASE_URL to ingress IP
   - Updated configmap YAML with correct Python code and environment variables
   - Updated overlay kustomization.yaml with BASE_URL patch

3. **9eb0313**: Remove Alertmanager resources blocking monitoring-stack sync
   - Problem: Alertmanager CRD not installed, broke Prometheus operator
   - Solution: Removed all Alertmanager references from helm-manifests.yaml

4. **6bdabdc**: Add missing PodMonitor and Probe CRDs to operator
   - Problem: Operator couldn't reconcile because PodMonitor/Probe CRDs missing
   - Solution: Extracted CRDs from official Helm chart, added to operator kustomization.yaml

5. **20918cd**: Add Backend API Four Golden Signals dashboard JSON
   - Adds dashboard JSON file for reference
   - Dashboard already mounted via ConfigMap in grafana-dashboard.yaml

## Testing the Deployment

### Quick Start: Port Forwarding Script

A convenient script is provided to manage all port forwards at once:

```bash
# Use the port-forwarding script
./scripts/port-forwards.sh

# Choose option 1 to deploy all port forwards
# The script automatically:
# - Switches to correct Kubernetes contexts
# - Detects existing port forwards and continues
# - Runs all services in background

# Access points:
# - Grafana:     http://localhost:3000
# - Locust:      http://localhost:8089
# - Prometheus:  http://localhost:9090

# To close all port forwards:
# ./scripts/port-forwards.sh
# Choose option 2
```

### Verify All Components Are Running

```bash
# Check all monitoring pods
kubectl get pods -n monitoring -l app.kubernetes.io/managed-by=argocd

# Expected output:
# prometheus-operator pod
# prometheus StatefulSet pod (1/1 READY, 2/2 containers)
# grafana pod
# node-exporter pod
# kube-state-metrics pod

# Verify all CRDs are present
kubectl get crd | grep monitoring.coreos.com

# Expected output: 5 CRDs
# - podmonitors.monitoring.coreos.com
# - probes.monitoring.coreos.com
# - prometheuses.monitoring.coreos.com
# - prometheusrules.monitoring.coreos.com
# - servicemonitors.monitoring.coreos.com
```

### Access Grafana

```bash
# Option 1: Use the port-forwarding script (recommended)
./scripts/port-forwards.sh
# Then open: http://localhost:3000

# Option 2: Manual port forward
kubectl port-forward svc/monitoring-stack-grafana -n monitoring 3000:80
# Open: http://localhost:3000

# Default credentials: admin / prom-operator
# Navigate to: Dashboards → Four Golden Signals
```

### Verify Prometheus Scraping Backend

```bash
# Query Prometheus API
kubectl exec prometheus-monitoring-stack-kube-prom-prometheus-0 -n monitoring -- \
  curl -s 'http://localhost:9090/api/v1/targets' | jq '.data.activeTargets | length'

# Should show multiple active targets including:
# - prometheus (self)
# - node-exporter
# - kube-state-metrics
# - grafana (if ServiceMonitor configured)
# - backend (if Backend exposes /metrics endpoint)
```

### Load Testing with Locust

Locust is deployed in the separate loadtest cluster and generates realistic traffic to test the monitoring setup.

**Locust Configuration:**
- File: `/INFRA/kustomize/locust/base/locustfile.py`
- Base URL: `http://172.18.0.5` (ingress controller IP for metric capture)
- Tasks: 3 HTTP endpoints with weighted distribution

**Locust Tasks:**
1. **root** (weight 10): `GET /` - Frontend HTML response
2. **get_projects** (weight 5): `GET /api/projects` - Backend API endpoint
3. **health** (weight 2): `GET /health` - Health check endpoint

**To Run Load Test:**

```bash
# 1. Port forward Locust UI
./scripts/port-forwards.sh
# Choose option 1

# 2. Open Locust: http://localhost:8089

# 3. Configure and start:
# - Number of users: 10-50 (for visible metrics)
# - Spawn rate: 1-5 users/sec
# - Run time: 5-10 minutes

# 4. Monitor in Grafana (http://localhost:3000):
# - Watch Traffic panel: RPS should increase
# - Watch Latency panel: Response times visible
# - Watch Errors panel: Should stay near 0%
# - Watch Saturation panel: CPU/Memory usage updates
```

### Key Prometheus Queries for Monitoring

These queries work in both Prometheus UI and Grafana panels:

**1. Request Rate (Requests Per Second)**
```promql
sum(rate(http_requests_total[5m]))
```
Shows total RPS across all endpoints.

**2. Request Rate by Endpoint**
```promql
sum(rate(http_requests_total[5m])) by (path)
```
Shows which endpoints are receiving traffic.

**3. Request Rate by Status Code**
```promql
sum(rate(http_requests_total[5m])) by (status)
```
Shows distribution of responses: 200 (success), 404, 500, etc.

**4. P95 Response Latency**
```promql
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```
95th percentile response time in seconds (more meaningful than averages).

**5. P99 Response Latency**
```promql
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
```
99th percentile response time (shows tail latencies).

**6. Error Rate (5xx responses as percentage)**
```promql
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) * 100
```
Percentage of requests that resulted in server errors.

**7. Total Errors Per Endpoint**
```promql
sum(rate(http_requests_total{status=~"5.."}[5m])) by (path)
```
Shows which endpoints are failing most frequently.

**8. CPU Usage by Pod**
```promql
rate(container_cpu_usage_seconds_total[5m])
```
CPU utilization of each container (pod).

**9. Memory Usage by Pod**
```promql
container_memory_usage_bytes
```
Current memory consumption of each pod.

**10. Memory Usage as % of Limit**
```promql
container_memory_usage_bytes / container_spec_memory_limit_bytes * 100
```
Memory usage relative to the pod's limit (saturation metric).

**To Use These Queries:**
1. Open Prometheus: http://localhost:9090
2. Paste any query into the search box
3. Click "Execute" or press Enter
4. View real-time graph and metrics table
5. Click "Graph" tab to see visualization over time



## What Changed From Original Setup

| Aspect | Before | After | Why |
|--------|--------|-------|-----|
| Alertmanager | Included (but CRD missing) | Removed | Not required, CRD not installed |
| CRDs | Only 3 of 5 | All 5 | Operator needs all for reconciliation |
| Dashboard | None | Four Golden Signals | Required by Extra 3 |
| KEDA Trigger | N/A | Prometheus metric | Scales on request rate |
| Sync Waves | Not enforced | -3 (CRDs), -1 (apps) | Ensures CRDs before resources using them |

## Key Learnings

1. **CRD Order Matters**: CustomResourceDefinitions must exist before resources that use them
2. **Prometheus is Observable**: Can query Prometheus to debug operator state
3. **Four Golden Signals Framework**: Latency, Traffic, Errors, Saturation gives complete picture
4. **KEDA Prevents Cascade**: Scaling on metrics instead of resource usage prevents overload
5. **DNS Across Clusters**: In multi-cluster setups, use direct IPs instead of DNS names
6. **ConfigMap in Kustomize**: When using `locustfile.py` file, update the actual file not just the configmap YAML
7. **Ingress vs LoadBalancer**: For metrics capture, traffic must flow through ingress controller (where Prometheus scrapes)

## Troubleshooting

### Locust Tasks Not Showing in UI

**Problem:** Locust web UI only shows 2 tasks instead of 3 (missing `/api/projects`)

**Root Cause:** ConfigMap was using old version of locustfile.py

**Solution:**
```bash
# 1. Update INFRA/kustomize/locust/base/locustfile.py with all 3 tasks
# 2. Commit and push to GitHub
# 3. ArgoCD syncs automatically
# 4. Restart locust pods:
kubectl delete pods -n locust -l app=locust

# 5. Verify 3 tasks are loaded:
kubectl exec -n locust deployment/locust-master -- grep -c "@task" /mnt/locust/locustfile.py
# Should output: 3
```

### Metrics Not Appearing in Grafana

**Problem:** Grafana dashboards show no data while Locust is running

**Root Cause:** Locust is targeting wrong IP (loadbalancer instead of ingress)

**Solution:**
```bash
# 1. Verify Locust is hitting ingress (172.18.0.5), not loadbalancer (172.18.0.7)
# 2. Check BASE_URL in deployment:
kubectl get deployment -n locust locust-master -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="BASE_URL")].value}'

# Should output: http://172.18.0.5

# 3. If wrong, update INFRA/kustomize/locust/overlays/loadtest/kustomization.yaml
# 4. Commit, push, and pods will auto-restart
```

### Port Forward Script Not Working

**Problem:** `./scripts/port-forwards.sh` shows "Port already in use" for all services

**Solution:**
```bash
# Kill all existing port forwards
pkill -f "kubectl.*port-forward"

# Then run script again
./scripts/port-forwards.sh
# Choose option 1
```

### Prometheus Targets Showing DOWN

**Problem:** Some targets in Prometheus UI show as DOWN instead of UP

**Solution:**
```bash
# 1. Check target details in Prometheus UI
# Go to: http://localhost:9090/targets

# 2. Click on DOWN target to see error
# Common causes:
# - Service doesn't exist (typo in job config)
# - Service port wrong (usually port name is "metrics", not actual number)
# - ServiceMonitor selector doesn't match service labels

# 3. Verify services exist:
kubectl get svc -n monitoring

# 4. Check ServiceMonitor label selectors:
kubectl get servicemonitor -n monitoring -o yaml | grep -A 5 selector
```

## References

- [kube-prometheus-stack Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Four Golden Signals](https://sre.google/sre-book/monitoring-distributed-systems/)
- [KEDA Documentation](https://keda.sh/docs/)
- [ArgoCD Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
