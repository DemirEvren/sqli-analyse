#!/usr/bin/env bash
# ─── bootstrap-aks.sh ────────────────────────────────────────────────────────
# Run this ONCE after `terraform apply` to install ArgoCD on both clusters
# and deploy all workloads via GitOps.
#
# This script mirrors INFRA/OPERATIONS.md but targets AKS instead of k3d.
#
# Prerequisites:
#   • terraform apply completed successfully
#   • export KUBECONFIG=<path>/kubeconfigs/merged.yaml  (or run from terraform/)
#   • GITHUB_TOKEN, POSTGRES_PASSWORD, JWT_SECRET set in environment
#   • kubectl, helm, jq, curl installed
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"   # kubernetes-app/
INFRA_DIR="${REPO_ROOT}/INFRA"

# ─── Cluster context names (must match AKS cluster names) ────────────────────
APP_CONTEXT="${APP_CLUSTER_NAME:-shelfware-app}"
LOADTEST_CONTEXT="${LOADTEST_CLUSTER_NAME:-shelfware-loadtest}"

# ─── Secrets (from environment — NOT hardcoded) ───────────────────────────────
GITHUB_TOKEN="${GITHUB_TOKEN:?GITHUB_TOKEN env var required}"
GITHUB_USERNAME="${GITHUB_USERNAME:-DemirEvren}"
GITHUB_REPO_URL="${GITHUB_REPO_URL:-https://github.com/DemirEvren/sqli-analyse.git}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD env var required}"
JWT_SECRET="${JWT_SECRET:?JWT_SECRET env var required}"

# ─── ArgoCD version ───────────────────────────────────────────────────────────
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.11.3}"

# ─────────────────────────────────────────────────────────────────────────────
log()  { echo "[$(date '+%H:%M:%S')] INFO  $*"; }
warn() { echo "[$(date '+%H:%M:%S')] WARN  $*"; }
fail() { echo "[$(date '+%H:%M:%S')] ERROR $*" >&2; exit 1; }

check_prereqs() {
  for cmd in kubectl helm jq curl az; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Required tool not found: $cmd"
  done

  # Verify KUBECONFIG is set and the merged file exists
  if [ -z "${KUBECONFIG:-}" ]; then
    # Default to the path written by the local_file Terraform resource
    SCRIPT_TF_DIR="$(cd "${SCRIPT_DIR}" && pwd)"
    export KUBECONFIG="${SCRIPT_TF_DIR}/kubeconfigs/merged.yaml"
  fi

  if [ ! -f "${KUBECONFIG}" ]; then
    fail "KUBECONFIG file not found: ${KUBECONFIG}
  Make sure you ran:
    cd INFRA/terraform
    terraform apply   (or the two-stage apply for a fresh workspace)
  then:
    export KUBECONFIG=${KUBECONFIG}"
  fi

  log "Prerequisites OK"
  log "KUBECONFIG: ${KUBECONFIG}"
}

wait_for_deployment() {
  local context="$1" namespace="$2" deployment="$3"
  log "Waiting for deployment/$deployment in $namespace ($context)..."
  kubectl wait --for=condition=available \
    --timeout=300s \
    deployment/"$deployment" \
    -n "$namespace" \
    --context "$context"
}

wait_for_rollout() {
  local context="$1" kind="$2" name="$3" namespace="$4"
  kubectl rollout status "$kind/$name" \
    -n "$namespace" \
    --context "$context" \
    --timeout=300s
}

# ─────────────────────────────────────────────────────────────────────────────
install_argocd() {
  local context="$1"
  log "Installing ArgoCD ${ARGOCD_VERSION} on ${context}..."

  # Apply the kustomize-managed ArgoCD install (same as k3d)
  kubectl apply -k "${INFRA_DIR}/argocd" --context "$context"

  wait_for_deployment "$context" argocd argocd-server
  wait_for_deployment "$context" argocd argocd-repo-server
  kubectl wait --for=condition=ready \
    --timeout=300s pod \
    -l app.kubernetes.io/name=argocd-application-controller \
    -n argocd \
    --context "$context"

  log "ArgoCD installed on ${context} ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
add_repo_credentials() {
  local context="$1"
  log "Adding ArgoCD repository credentials on ${context}..."

  # Terraform already created the secret, but ArgoCD must restart to pick it up
  # if it was created before ArgoCD was installed. Patch to trigger a reload.
  kubectl rollout restart deployment/argocd-repo-server \
    -n argocd --context "$context" || true

  log "Repo credentials ready on ${context} ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
create_app_secrets() {
  log "Ensuring shelfware secrets exist on ${APP_CONTEXT}..."

  for ns in prod-shelfware test-shelfware; do
    kubectl create namespace "$ns" \
      --context "$APP_CONTEXT" \
      --dry-run=client -o yaml | kubectl apply -f - --context "$APP_CONTEXT"

    # Upsert postgres-secret (Terraform created this but we keep it idempotent)
    kubectl create secret generic postgres-secret \
      -n "$ns" \
      --context "$APP_CONTEXT" \
      --from-literal=database-url="postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/shelfware?schema=public" \
      --from-literal=postgres-password="${POSTGRES_PASSWORD}" \
      --from-literal=jwt-secret="${JWT_SECRET}" \
      --from-literal=password="${POSTGRES_PASSWORD}" \
      --dry-run=client -o yaml | kubectl apply -f - --context "$APP_CONTEXT"

    # Image pull secret for ghcr.io
    kubectl create secret docker-registry ghcr-credentials \
      -n "$ns" \
      --context "$APP_CONTEXT" \
      --docker-server=ghcr.io \
      --docker-username="${GITHUB_USERNAME}" \
      --docker-password="${GITHUB_TOKEN}" \
      --dry-run=client -o yaml | kubectl apply -f - --context "$APP_CONTEXT"

    log "  ✓ secrets in namespace $ns"
  done
}

# ─────────────────────────────────────────────────────────────────────────────
deploy_app_cluster() {
  log "=== APP CLUSTER: ${APP_CONTEXT} ==="

  install_argocd "$APP_CONTEXT"
  add_repo_credentials "$APP_CONTEXT"
  create_app_secrets

  log "Applying ArgoCD root Application (app cluster)..."
  kubectl apply -f "${INFRA_DIR}/argocd/applications/appcluster/root-app.yaml" \
    --context "$APP_CONTEXT"

  log "ArgoCD will now sync the following Applications:"
  log "  • ingress-nginx   (sync-wave -3)"
  log "  • prometheus-operator (sync-wave -2)"
  log "  • monitoring-stack    (sync-wave -1)"
  log "  • keda                (sync-wave  0)"
  log "  • shelfware-test      (sync-wave  1)"
  log "  • shelfware-prod      (sync-wave  2)"
  log ""
  log "Monitor sync progress:"
  log "  kubectl get applications -n argocd --context ${APP_CONTEXT} -w"
}

# ─────────────────────────────────────────────────────────────────────────────
deploy_loadtest_cluster() {
  log "=== LOADTEST CLUSTER: ${LOADTEST_CONTEXT} ==="

  install_argocd "$LOADTEST_CONTEXT"
  add_repo_credentials "$LOADTEST_CONTEXT"

  log "Applying ArgoCD root Application (loadtest cluster)..."
  kubectl apply -f "${INFRA_DIR}/argocd/applications/loadtest/root-app.yaml" \
    --context "$LOADTEST_CONTEXT"

  log "Locust will be deployed to the 'locust' namespace ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
wait_for_ingress() {
  log "Waiting for ingress-nginx LoadBalancer IP..."

  local max_attempts=60
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    INGRESS_IP=$(kubectl get svc ingress-nginx-controller \
      -n ingress-nginx \
      --context "$APP_CONTEXT" \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

    if [ -n "$INGRESS_IP" ]; then
      log "Ingress IP: ${INGRESS_IP}"
      break
    fi

    attempt=$((attempt + 1))
    sleep 10
    echo -n "."
  done

  if [ -z "${INGRESS_IP:-}" ]; then
    warn "Ingress IP not yet available. Check: kubectl get svc -n ingress-nginx --context ${APP_CONTEXT}"
    return
  fi

  echo ""
  log ""
  log "═══ DNS Configuration ══════════════════════════════════════════════"
  log "Add to /etc/hosts (local testing):"
  log "  ${INGRESS_IP}  shelfware.local test.shelfware.local"
  log ""
  log "OR configure your Azure DNS zone:"
  log "  az network dns record-set a add-record \\"
  log "    --resource-group rg-shelfware-tfstate \\"
  log "    --zone-name <your-zone> \\"
  log "    --record-set-name '@' \\"
  log "    --ipv4-address ${INGRESS_IP}"
  log "════════════════════════════════════════════════════════════════════"
}

# ─────────────────────────────────────────────────────────────────────────────
smoke_test() {
  log "Running smoke tests..."

  local max_wait=600  # 10 minutes for ArgoCD to sync everything
  local elapsed=0

  log "Waiting for ArgoCD sync (up to ${max_wait}s)..."
  while [ $elapsed -lt $max_wait ]; do
    synced=$(kubectl get applications -n argocd \
      --context "$APP_CONTEXT" \
      -o jsonpath='{.items[*].status.sync.status}' 2>/dev/null || true)

    all_synced=true
    for status in $synced; do
      if [ "$status" != "Synced" ]; then
        all_synced=false
        break
      fi
    done

    if $all_synced && [ -n "$synced" ]; then
      log "All Applications synced ✓"
      break
    fi

    elapsed=$((elapsed + 30))
    sleep 30
    echo -n "."
  done

  echo ""

  if [ -n "${INGRESS_IP:-}" ]; then
    log "Testing PROD endpoint..."
    curl --silent --max-time 10 \
      -H "Host: shelfware.local" \
      "http://${INGRESS_IP}/" \
      -o /dev/null -w "  PROD /            → HTTP %{http_code}\n" || true

    curl --silent --max-time 10 \
      -H "Host: shelfware.local" \
      "http://${INGRESS_IP}/api/projects" \
      -o /dev/null -w "  PROD /api/projects → HTTP %{http_code}\n" || true

    log "Testing TEST endpoint..."
    curl --silent --max-time 10 \
      -H "Host: test.shelfware.local" \
      "http://${INGRESS_IP}/" \
      -o /dev/null -w "  TEST /            → HTTP %{http_code}\n" || true
  else
    warn "Skipping HTTP smoke tests (no ingress IP yet)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
print_summary() {
  log ""
  log "═══ Deployment Summary ══════════════════════════════════════════════"
  log ""
  log "App Cluster:      ${APP_CONTEXT}"
  log "Loadtest Cluster: ${LOADTEST_CONTEXT}"
  log ""
  log "Useful commands:"
  log ""
  log "  # Watch ArgoCD sync:"
  log "  kubectl get applications -n argocd --context ${APP_CONTEXT} -w"
  log ""
  log "  # Port-forward ArgoCD UI:"
  log "  kubectl port-forward svc/argocd-server -n argocd 8080:443 --context ${APP_CONTEXT}"
  log "  # → https://localhost:8080  (user: admin, pass from below)"
  log "  kubectl get secret argocd-initial-admin-secret -n argocd --context ${APP_CONTEXT} -o jsonpath='{.data.password}' | base64 -d"
  log ""
  log "  # Port-forward Grafana:"
  log "  kubectl port-forward svc/monitoring-stack-grafana -n monitoring 3000:80 --context ${APP_CONTEXT}"
  log "  # → http://localhost:3000  (user: admin / prom-operator)"
  log ""
  log "  # Port-forward Prometheus:"
  log "  kubectl port-forward svc/monitoring-stack-kube-prom-prometheus -n monitoring 9090:9090 --context ${APP_CONTEXT}"
  log ""
  log "  # Run Locust load test:"
  log "  kubectl port-forward svc/locust-master -n locust 8089:8089 --context ${LOADTEST_CONTEXT}"
  log "  # → http://localhost:8089"
  log ""
  log "════════════════════════════════════════════════════════════════════"
}

# ─────────────────────────────────────────────────────────────────────────────
main() {
  check_prereqs

  log "Bootstrap starting..."
  log "  App cluster:      ${APP_CONTEXT}"
  log "  Loadtest cluster: ${LOADTEST_CONTEXT}"
  log ""

  deploy_app_cluster
  deploy_loadtest_cluster
  wait_for_ingress
  smoke_test
  print_summary
}

main "$@"
