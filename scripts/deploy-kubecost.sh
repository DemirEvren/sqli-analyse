#!/bin/bash
set -euo pipefail

CLUSTER_NAME="shelfware-app"
KUBECOST_NAMESPACE="kubecost"

echo "=========================================="
echo "  Kubecost Deployment (via Helm)"
echo "=========================================="

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Switch to correct context
echo ""
echo "=== Switching to cluster context ==="
kubectl config use-context "k3d-$CLUSTER_NAME"
sleep 2

# Verify Prometheus is running
echo ""
echo "=== Verifying Prometheus is available ==="
if kubectl get svc -n monitoring prometheus-operated &>/dev/null; then
  echo "[OK] Prometheus found in monitoring namespace"
else
  echo "[WARN] Prometheus not found - Kubecost may not collect metrics properly"
fi

# Create namespace
echo ""
echo "=== Creating Kubecost namespace ==="
kubectl create namespace $KUBECOST_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
echo "[OK] Namespace created"

# Add Helm repo (or update if already exists)
echo ""
echo "=== Adding/Updating Kubecost Helm repository ==="
helm repo add kubecost https://kubecost.github.io/kubecost 2>/dev/null || helm repo update kubecost
helm repo update
echo "[OK] Helm repo ready"

# Create values file for Helm
echo ""
echo "=== Creating Helm values configuration ==="
cat > /tmp/kubecost-values.yaml << 'EOF'
# Kubecost 2.8.6 - use external Prometheus
global:
  clusterId: shelfware-app
  prometheus:
    enabled: false
    fqdn: http://monitoring-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090

# Reduce resource usage for testing
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

# Disable ingress for now (use port-forward instead)
ingress:
  enabled: false
EOF

echo "[OK] Values configuration created"

# Install Kubecost via Helm (using 2.8.6 - stable version)
echo ""
echo "=== Installing Kubecost via Helm (v2.8.6) ==="
helm upgrade --install kubecost kubecost/cost-analyzer \
  --version 2.8.6 \
  --namespace $KUBECOST_NAMESPACE \
  --values /tmp/kubecost-values.yaml \
  --wait \
  --timeout 5m

echo "[OK] Kubecost Helm release installed"

# Wait for deployment
echo ""
echo "=== Waiting for Kubecost pods to be ready ==="
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=kubecost \
  -n $KUBECOST_NAMESPACE \
  --timeout=300s \
  || echo "[WARN] Some pods not yet ready (continuing)"

# Show pod status
echo ""
echo "=== Kubecost Pod Status ==="
kubectl get pods -n $KUBECOST_NAMESPACE

# Get services
echo ""
echo "=== Kubecost Services ==="
kubectl get svc -n $KUBECOST_NAMESPACE

echo ""
echo "=========================================="
echo "  [SUCCESS] Kubecost Deployment Complete!"
echo "=========================================="
echo ""
echo "To access Kubecost UI:"
echo "  kubectl port-forward -n $KUBECOST_NAMESPACE svc/kubecost 9090:9090"
echo ""
echo "Then open in browser:"
echo "  http://localhost:9090"
echo ""
echo "Monitor pods:"
echo "  kubectl get pods -n $KUBECOST_NAMESPACE -w"
echo ""
echo "View logs:"
echo "  kubectl logs -n $KUBECOST_NAMESPACE -l app.kubernetes.io/name=kubecost -f"
echo ""
