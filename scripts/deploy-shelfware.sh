#!/bin/bash
set -euo pipefail

CLUSTER_NAME="shelfware-app"
SHARED_NETWORK="k3d-shared"

# Secrets (NOT in Git - defined here)
GITHUB_TOKEN="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"
GITHUB_USERNAME="DemirEvren"
GITHUB_REPO_URL="https://github.com/PXL-Systems-Expert/2526-ex-DemirEvren.git"
POSTGRES_PASSWORD="postgres"
JWT_SECRET="c3a68d7c-dc34-4e5f-bf1a-705062c81c53"

echo "=========================================="
echo "  Shelfware App Cluster Deployment"
echo "=========================================="

cd ~/kubernetes/2526-ex-DemirEvren

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

kubectl config use-context "k3d-$CLUSTER_NAME"

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
sleep 30

# COMMAND 3: Deploy Applications
echo ""
echo "=== COMMAND 3: Deploy Applications ==="
kubectl apply -f INFRA/argocd/applications/appcluster/

echo ""
echo "=========================================="
echo "  ✅ Deployment Complete!"
echo "=========================================="
echo ""
echo "Monitor:"
echo "  kubectl get applications -n argocd -w"
echo "  kubectl get pods -A"
echo ""
echo "ArgoCD UI:"
echo "  kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo "  admin / \$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo ""