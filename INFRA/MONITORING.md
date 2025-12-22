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

1. **9eb0313**: Remove Alertmanager resources blocking monitoring-stack sync
   - Problem: Alertmanager CRD not installed, broke Prometheus operator
   - Solution: Removed all Alertmanager references from helm-manifests.yaml

2. **6bdabdc**: Add missing PodMonitor and Probe CRDs to operator
   - Problem: Operator couldn't reconcile because PodMonitor/Probe CRDs missing
   - Solution: Extracted CRDs from official Helm chart, added to operator kustomization.yaml

3. **20918cd**: Add Backend API Four Golden Signals dashboard JSON
   - Adds dashboard JSON file for reference
   - Dashboard already mounted via ConfigMap in grafana-dashboard.yaml

## Testing the Deployment

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
# Port forward to Grafana
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

## References

- [kube-prometheus-stack Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Four Golden Signals](https://sre.google/sre-book/monitoring-distributed-systems/)
- [KEDA Documentation](https://keda.sh/docs/)
- [ArgoCD Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
