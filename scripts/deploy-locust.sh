#!/bin/bash
set -euo pipefail

CLUSTER_NAME="shelfware-loadtest"
SHARED_NETWORK="k3d-shared"
ARGOCD_NAMESPACE="argocd"
GITHUB_REPO_URL="https://github.com/PXL-Systems-Expert/2526-ex-DemirEvren.git"
GITHUB_USERNAME="DemirEvren"
GITHUB_TOKEN="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"
GITHUB_EMAIL="evrenhulk@gmail.com"

echo "=========================================="
echo "  Shelfware Loadtest Cluster Deployment"
echo "=========================================="

# Step 0: Ensure shared network exists
echo ""
echo "=== Verify Shared Docker Network ==="
if docker network inspect "$SHARED_NETWORK" >/dev/null 2>&1; then
  echo "✓ Network '$SHARED_NETWORK' exists"
else
  echo "❌ Network '$SHARED_NETWORK' does not exist!"
  echo "Run deploy-app.sh first to create the app cluster and shared network"
  exit 1
fi

# Step 1: Clean existing cluster
echo ""
echo "=== Removing existing cluster (if any) ==="
k3d cluster delete "$CLUSTER_NAME" 2>/dev/null && echo "✓ Old cluster removed" || echo "✓ No existing cluster"

# Step 2: Create cluster (1 command!)
echo ""
echo "=== STEP 1: Create k3d cluster ==="
k3d cluster create "$CLUSTER_NAME" \
  --network "$SHARED_NETWORK" \
  --servers 1 \
  --agents 2 \
  --no-lb \
  --k3s-arg "--disable=metrics-server@server:0" \
  --k3s-arg "--disable=metrics-server@server:*"

echo "✓ Cluster created on network: $SHARED_NETWORK"

# Give kubeconfig time to be written
sleep 5

# Get kubeconfig and merge it into main config
echo "Merging kubeconfig..."
k3d kubeconfig get "$CLUSTER_NAME" 2>/dev/null > /tmp/loadtest-kb.yaml
if [ -s /tmp/loadtest-kb.yaml ]; then
  KUBECONFIG=~/.kube/config:/tmp/loadtest-kb.yaml kubectl config view --flatten > ~/.kube/config.merged 2>/dev/null
  if [ -s ~/.kube/config.merged ]; then
    mv ~/.kube/config.merged ~/.kube/config
    echo "✓ Kubeconfig merged successfully"
  fi
fi

# Switch context
kubectl config use-context "k3d-$CLUSTER_NAME" 2>/dev/null || echo "Retrying context switch..."
sleep 2
kubectl config use-context "k3d-$CLUSTER_NAME"

# Step 3: Install ArgoCD
echo ""
echo "=== STEP 2: Install ArgoCD ==="
kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n "$ARGOCD_NAMESPACE" -f ../INFRA/argocd/install.yaml

# Patch repo-server to reduce ephemeral storage usage
echo "Patching ArgoCD repo-server to reduce storage pressure..."
kubectl patch deployment argocd-repo-server -n "$ARGOCD_NAMESPACE" --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources", "value": {"requests": {"memory": "128Mi"}, "limits": {"memory": "256Mi"}}}]' 2>/dev/null || true

# Clean up ArgoCD's git cache directory on the node to free space
kubectl exec -n "$ARGOCD_NAMESPACE" -it deployment/argocd-server -- sh -c 'rm -rf /tmp/argocd-* 2>/dev/null' 2>/dev/null || true

echo "Waiting for ArgoCD to be ready..."
# Use shorter timeout and allow failures - ArgoCD might still be initializing
kubectl wait --for=condition=available --timeout=60s \
  deployment/argocd-server \
  -n "$ARGOCD_NAMESPACE" 2>/dev/null || echo "⚠️  argocd-server not ready, continuing anyway..."

# Wait for repo-server with a shorter timeout
kubectl rollout status deployment/argocd-repo-server -n "$ARGOCD_NAMESPACE" --timeout=60s 2>/dev/null || echo "⚠️  argocd-repo-server not ready, continuing anyway..."

# Give deployments a moment to stabilize
sleep 15

echo "✓ ArgoCD deployment started (may still be initializing)"

# Step 4: Configure GitHub credentials
echo ""
echo "=== STEP 3: Configure GitHub Repository Access ==="
kubectl delete secret repo-creds -n "$ARGOCD_NAMESPACE" --ignore-not-found

kubectl create secret generic repo-creds \
  -n "$ARGOCD_NAMESPACE" \
  --from-literal=type=git \
  --from-literal=url="$GITHUB_REPO_URL" \
  --from-literal=username="$GITHUB_USERNAME" \
  --from-literal=password="$GITHUB_TOKEN"

kubectl label secret repo-creds \
  -n "$ARGOCD_NAMESPACE" \
  argocd.argoproj.io/secret-type=repository --overwrite

echo "✓ GitHub credentials configured"

# Step 5: Deploy Locust
echo ""
echo "=== STEP 4: Deploy Locust via ArgoCD ==="
kubectl apply -n "$ARGOCD_NAMESPACE" -f ../INFRA/argocd/applications/loadtest/root-app.yaml

echo ""
echo "=========================================="
echo "  ✅ Loadtest Cluster Deployment Complete!"
echo "=========================================="
echo ""
echo "⚠️  IMPORTANT: Configure Locust to reach the app cluster"
echo "   The loadtest cluster needs to access the app cluster's ingress."
echo "   Set the BASE_URL environment variable when deploying Locust:"
echo ""
echo "   For cross-cluster access via shared Docker network:"
echo "   BASE_URL=http://k3d-shelfware-app-serverlb:80"
echo ""
echo "   Or via the app cluster's ingress IP:"
echo "   BASE_URL=http://172.18.0.2"
echo ""
echo "Cluster Info:"
echo "  Name: $CLUSTER_NAME"
echo "  Context: k3d-$CLUSTER_NAME"
echo "  Network: $SHARED_NETWORK"
echo ""
echo "Locust UI:"
echo "  kubectl port-forward -n locust svc/locust-master 8089:8089"
echo "  URL: http://localhost:8089"
echo ""
echo "Next Steps:"
echo "  1. Wait for Locust to deploy"
echo "     kubectl get pods -n locust -w"
echo "  2. Check application status"
echo "     kubectl get application -n argocd"
echo "  3. Port-forward Locust UI"
echo "     kubectl port-forward -n locust svc/locust-master 8089:8089"
echo "  4. Run load test against PROD"
echo "     Target: http://k3d-shelfware-app-serverlb"
echo "     Host header: shelfware.local"
echo ""
