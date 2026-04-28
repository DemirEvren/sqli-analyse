#!/bin/bash

###############################################################################
# Shelfware Post-Deployment — Port-Forward Setup
###############################################################################

set -e

KUBECONFIG_PATH="${KUBECONFIG:=$(pwd)/INFRA/terraform/kubeconfigs/merged-admin.yaml}"
CONTEXT="shelfware-app-admin"
HOST_IP="192.168.2.56"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Setting up Port-Forwarding for Local Development           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check kubeconfig
if [ ! -f "$KUBECONFIG_PATH" ]; then
    echo "❌ ERROR: kubeconfig not found at $KUBECONFIG_PATH"
    echo "   Please ensure terraform has been applied first."
    exit 1
fi

export KUBECONFIG="$KUBECONFIG_PATH"

# Verify context exists
if ! kubectl config get-contexts "$CONTEXT" &>/dev/null; then
    echo "❌ ERROR: Context '$CONTEXT' not found in kubeconfig"
    echo "   Available contexts:"
    kubectl config get-contexts
    exit 1
fi

echo "✓ kubeconfig configured"
echo ""

# Check if /etc/hosts has the entry
if ! grep -q "shelfware.local" /etc/hosts; then
    echo "⚠ WARNING: shelfware.local not in /etc/hosts"
    echo "   Add these lines to /etc/hosts:"
    echo ""
    echo "   127.0.0.1  shelfware.local"
    echo "   127.0.0.1  test.shelfware.local"
    echo ""
    read -p "   Continue anyway? (y/n) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

echo "✓ DNS resolution ready"
echo ""

# Wait for ingress-nginx to be ready
echo "Waiting for ingress-nginx controller..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/component=controller \
  -n ingress-nginx \
  --context "$CONTEXT" \
  --timeout=120s 2>/dev/null || true

echo "✓ ingress-nginx ready"
echo ""

echo "════════════════════════════════════════════════════════════════"
echo "🚀 Starting Port-Forward"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "IMPORTANT: Keep this terminal open while developing!"
echo ""
echo "In another terminal, test with:"
echo "  curl http://shelfware.local:8080"
echo "  curl http://${HOST_IP}:8080 -H 'Host: shelfware.local'"
echo "  # or open browser to http://shelfware.local:8080"
echo ""
echo "Press Ctrl+C to stop port-forwarding"
echo ""

# Start port-forward
kubectl port-forward svc/ingress-nginx-controller -n ingress-nginx 8080:80 \
  --context "$CONTEXT" \
  --address 127.0.0.1,"$HOST_IP"