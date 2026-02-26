#!/bin/bash
set -euo pipefail

CLUSTER_NAME="shelfware-app"
SHARED_NETWORK="k3d-shared"
ARGOCD_NAMESPACE="argocd"

# Secrets (NOT in Git - defined here)
GITHUB_TOKEN=""  # Set your GitHub token here
GITHUB_USERNAME="DemirEvren"
GITHUB_REPO_URL="https://github.com/DemirEvren/sqli-analyse.git"
POSTGRES_PASSWORD="postgres"
JWT_SECRET="c3a68d7c-dc34-4e5f-bf1a-705062c81c53"

echo "=========================================="
echo "  Shelfware App Cluster Deployment"
echo "=========================================="

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Infrastructure
docker network create "$SHARED_NETWORK" 2>/dev/null || true
k3d cluster delete "$CLUSTER_NAME" 2>/dev/null || true

# COMMAND 1: Create cluster
echo ""
echo "=== COMMAND 1: Create k3d cluster ==="
k3d cluster create "$CLUSTER_NAME" \
  --network "$SHARED_NETWORK" \
  --servers 1 \
  --agents 2 \
  --port "80:80@loadbalancer" \
  --port "443:443@loadbalancer" \
  --k3s-arg "--disable=traefik@server:0"

# Switch context and verify
echo "Switching to cluster context..."
kubectl config use-context "k3d-$CLUSTER_NAME"
sleep 2

# Verify context switch
if [ "$(kubectl config current-context)" != "k3d-$CLUSTER_NAME" ]; then
  echo "❌ Context switch failed. Attempting manual switch..."
  kubectl config use-context "k3d-$CLUSTER_NAME" || exit 1
fi

# COMMAND 2: Deploy ArgoCD + Create Secrets
echo ""
echo "=== COMMAND 2: Deploy ArgoCD ==="
kubectl apply -k INFRA/argocd

# Wait for ArgoCD
echo "Waiting for ArgoCD..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-repo-server -n argocd
kubectl wait --for=condition=ready --timeout=300s \
  pod -l app.kubernetes.io/name=argocd-application-controller -n argocd

# COMMAND 2b: Deploy Ingress-nginx
echo ""
echo "=== COMMAND 2b: Deploy Ingress-nginx ==="
kubectl apply -f INFRA/ingress-nginx/install.yaml
echo "Waiting for ingress-nginx controller to be ready..."
kubectl wait --for=condition=ready --timeout=300s \
  pod -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx 2>/dev/null || echo "⚠️  Ingress-nginx may take longer to start"

# Create GitHub credentials secret (not in Git!)
echo "Creating GitHub credentials secret..."
kubectl create secret generic private-repo-creds \
  --namespace=argocd \
  --from-literal=type=git \
  --from-literal=url="$GITHUB_REPO_URL" \
  --from-literal=username="$GITHUB_USERNAME" \
  --from-literal=password="$GITHUB_TOKEN"

kubectl label secret private-repo-creds \
  argocd.argoproj.io/secret-type=repository \
  -n argocd

# Create application namespaces
echo "Creating application namespaces..."
kubectl create namespace prod-shelfware --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace test-shelfware --dry-run=client -o yaml | kubectl apply -f -

# Create Postgres secrets (not in Git!)
echo "Creating Postgres secrets..."
kubectl create secret generic postgres-secret \
  --from-literal=password="$POSTGRES_PASSWORD" \
  --from-literal=jwt-secret="$JWT_SECRET" \
  --from-literal=database-url="postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/shelfware?schema=public" \
  -n prod-shelfware

kubectl create secret generic postgres-secret \
  --from-literal=password="$POSTGRES_PASSWORD" \
  --from-literal=jwt-secret="$JWT_SECRET" \
  --from-literal=database-url="postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/shelfware?schema=public" \
  -n test-shelfware

echo "Waiting for ArgoCD to be fully ready..."
sleep 15

# Configure git credentials for ArgoCD repo-server (HTTPS private repo authentication)
echo "Configuring ArgoCD git credentials..."
# Use git URL rewriting to inject credentials
kubectl exec -n "$ARGOCD_NAMESPACE" deployment/argocd-repo-server -- git config --system url."https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/" 2>/dev/null || \
# Fallback: patch the repo-server pod to set GIT_ASKPASS
kubectl set env deployment/argocd-repo-server -n "$ARGOCD_NAMESPACE" GIT_TERMINAL_PROMPT=0 GITHUB_TOKEN="$GITHUB_TOKEN" 2>/dev/null || true
echo "✓ Git credentials configured"

sleep 5

# Restart repo-server to pick up any changes
kubectl rollout restart deployment/argocd-repo-server -n "$ARGOCD_NAMESPACE" 2>/dev/null || true
kubectl rollout status deployment/argocd-repo-server -n "$ARGOCD_NAMESPACE" --timeout=60s 2>/dev/null || true

sleep 5

# Fix CoreDNS endpoint discovery (orbstack/macOS issue)
echo "Verifying ArgoCD component connectivity..."
if ! kubectl get endpoints -n argocd argocd-repo-server -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | grep -q .; then
  echo "⚠️  ArgoCD repo-server endpoints not discovered. Restarting CoreDNS..."
  kubectl rollout restart deployment/coredns -n kube-system
  kubectl rollout status deployment/coredns -n kube-system --timeout=60s
  sleep 5
fi

# Verify ArgoCD repo-server is responsive
echo "Checking repo-server connectivity..."
max_attempts=10
attempt=0
while [ $attempt -lt $max_attempts ]; do
  if kubectl get endpoints -n argocd argocd-repo-server -o jsonpath='{.subsets[0].ports[0].port}' 2>/dev/null | grep -q .; then
    echo "✓ ArgoCD repo-server endpoints are ready"
    break
  fi
  echo "Waiting for repo-server endpoints... ($((attempt + 1))/$max_attempts)"
  sleep 3
  attempt=$((attempt + 1))
done

if [ $attempt -ge $max_attempts ]; then
  echo "⚠️  Warning: repo-server endpoints may not be ready, continuing anyway..."
fi

# COMMAND 3: Deploy Applications
echo ""
echo "=== COMMAND 3: Deploy Applications ==="

# Fix any old GitHub repo URLs in application manifests
echo "Updating application manifest URLs..."
find INFRA/argocd/applications -name "*.yaml" -exec sed -i '' \
  "s|https://github.com/PXL-Systems-Expert/2526-ex-DemirEvren.git|https://github.com/DemirEvren/sqli-analyse.git|g" {} \;
echo "✓ URLs updated"

kubectl apply -f INFRA/argocd/applications/appcluster/

# Wait for applications to sync
echo ""
echo "=== Waiting for Applications to Sync ==="
max_wait=300
elapsed=0
synced_count=0

while [ $elapsed -lt $max_wait ]; do
  synced_count=$(kubectl get applications -n argocd -o jsonpath='{.items[?(@.status.operationState.finishedAt)].metadata.name}' 2>/dev/null | wc -w)
  total_count=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
  
  if [ "$synced_count" -ge "$total_count" ] && [ "$total_count" -gt 0 ]; then
    echo "✓ All applications synced ($synced_count/$total_count)"
    break
  fi
  
  echo "Synced: $synced_count/$total_count applications"
  sleep 10
  elapsed=$((elapsed + 10))
done

# Verify key deployments are ready
echo ""
echo "=== Verifying Deployment Status ==="

# Check if prod-shelfware namespace has started deploying
if kubectl get deploy -n prod-shelfware 2>/dev/null | grep -q "frontend"; then
  echo "✓ Shelfware deployments are present"
else
  echo "⚠️  Shelfware deployments not yet visible"
fi

# Update /etc/hosts for local domain access
echo ""
echo "=== Configuring DNS (adding to /etc/hosts) ==="
HOSTS_ENTRY="127.0.0.1 shelfware.local test.shelfware.local"
if grep -q "shelfware.local" /etc/hosts; then
  echo "✓ Hosts entry already configured"
else
  echo "Adding localhost entry for shelfware domains..."
  echo "$HOSTS_ENTRY" | sudo tee -a /etc/hosts > /dev/null
  echo "✓ Added to /etc/hosts"
fi

echo ""
echo "=========================================="
echo "  ✅ Deployment Complete!"
echo "=========================================="
echo ""
echo "Next Steps:"
echo "  1. Monitor pod status:"
echo "     kubectl get pods -n prod-shelfware -w"
echo ""
echo "  2. Access ArgoCD UI:"
echo "     kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo "     admin / \$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo ""
echo "  3. Check application status:"
echo "     kubectl get applications -n argocd"
echo ""
echo "  4. Add domains to /etc/hosts:"
echo "     127.0.0.1 shelfware.local test.shelfware.local"
echo ""
echo ""
echo "Monitor:"
echo "  kubectl get applications -n argocd -w"
echo "  kubectl get pods -A"
echo ""
echo "ArgoCD UI:"
echo "  kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo "  admin / \$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo ""