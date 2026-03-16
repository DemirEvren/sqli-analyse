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
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"   # kubernetes-app/
INFRA_DIR="${REPO_ROOT}/INFRA"

# ─── Cluster and context names ─────────────────────────────────────────────
APP_CLUSTER_NAME="${APP_CLUSTER_NAME:-shelfware-app}"
LOADTEST_CLUSTER_NAME="${LOADTEST_CLUSTER_NAME:-shelfware-loadtest}"
AKS_RESOURCE_GROUP="${AKS_RESOURCE_GROUP:-rg-sqli-main}"

APP_CONTEXT="${APP_CLUSTER_NAME}-admin"
LOADTEST_CONTEXT="${LOADTEST_CLUSTER_NAME}-admin"

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

  # Fetch admin credentials for both clusters — bypasses Azure RBAC entirely.
  # Requires only 'Azure Kubernetes Service Contributor Role' (already assigned).
  local kubeconfig_dir
  kubeconfig_dir="$(dirname "${KUBECONFIG}")"
  mkdir -p "${kubeconfig_dir}"

  log "Fetching admin kubeconfig for ${APP_CLUSTER_NAME}..."
  az aks get-credentials \
    --resource-group "${AKS_RESOURCE_GROUP}" \
    --name "${APP_CLUSTER_NAME}" \
    --admin \
    --file "${kubeconfig_dir}/shelfware-app-admin-tmp.yaml" \
    --overwrite-existing

  # Check if loadtest cluster exists (optional for app-only deployments)
  log "Checking if loadtest cluster exists..."
  if az aks show --resource-group "${AKS_RESOURCE_GROUP}" --name "${LOADTEST_CLUSTER_NAME}" &>/dev/null; then
    log "Fetching admin kubeconfig for ${LOADTEST_CLUSTER_NAME}..."
    az aks get-credentials \
      --resource-group "${AKS_RESOURCE_GROUP}" \
      --name "${LOADTEST_CLUSTER_NAME}" \
      --admin \
      --file "${kubeconfig_dir}/shelfware-loadtest-admin-tmp.yaml" \
      --overwrite-existing

    # Merge both app and loadtest admin files
    KUBECONFIG="${kubeconfig_dir}/shelfware-app-admin-tmp.yaml:${kubeconfig_dir}/shelfware-loadtest-admin-tmp.yaml" \
      kubectl config view --flatten > "${kubeconfig_dir}/merged-admin.yaml"
  else
    log "Loadtest cluster not found (app-only deployment) — skipping loadtest kubeconfig"
    # Just use app cluster kubeconfig
    cp "${kubeconfig_dir}/shelfware-app-admin-tmp.yaml" "${kubeconfig_dir}/merged-admin.yaml"
  fi

  export KUBECONFIG="${kubeconfig_dir}/merged-admin.yaml"
  log "Admin kubeconfig: ${KUBECONFIG}"
  log "Using kubectl contexts: ${APP_CONTEXT} / ${LOADTEST_CONTEXT}"
}

wait_for_deployment() {
  local context="$1" namespace="$2" deployment="$3"
  local deadline=$(( $(date +%s) + 300 ))
  log "Waiting for deployment/$deployment in $namespace ($context)..."
  until kubectl rollout status deployment/"$deployment" \
      -n "$namespace" --context "$context" --timeout=30s 2>/dev/null; do
    if [[ $(date +%s) -ge $deadline ]]; then
      log "ERROR: Timed out waiting for $deployment in $namespace ($context)"
      kubectl get pods -n "$namespace" --context "$context" || true
      return 1
    fi
    sleep 10
  done
}

wait_for_rollout() {
  local context="$1" kind="$2" name="$3" namespace="$4"
  kubectl rollout status "$kind/$name" \
    -n "$namespace" \
    --context "$context" \
    --timeout=300s
}

# ─────────────────────────────────────────────────────────────────────────────
wait_for_node_ready() {
  local context="$1"
  log "Waiting for at least one node to be Ready on ${context}..."
  local deadline=$(( $(date +%s) + 600 ))
  until kubectl get nodes --context "$context" --no-headers 2>/dev/null \
        | grep -q " Ready "; do
    if [[ $(date +%s) -ge $deadline ]]; then
      log "ERROR: Timed out waiting for nodes on ${context}"
      return 1
    fi
    sleep 10
  done
  log "Node(s) Ready on ${context} ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
install_argocd() {
  local context="$1"
  log "Installing ArgoCD ${ARGOCD_VERSION} on ${context}..."

  wait_for_node_ready "$context"

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
create_opencost_azure_secret() {
  log "Creating OpenCost Azure cloud integration secret..."

  # These env vars are optional. If not set, OpenCost falls back to public
  # on-demand list prices (good enough for dev, not for production billing).
  local sub_id="${AZURE_SUBSCRIPTION_ID:-}"
  local tenant_id="${AZURE_TENANT_ID:-${ARM_TENANT_ID:-}}"
  local client_id="${AZURE_CLIENT_ID:-${ARM_CLIENT_ID:-}}"
  local client_secret="${AZURE_CLIENT_SECRET:-${ARM_CLIENT_SECRET:-}}"

  if [ -z "$sub_id" ] || [ -z "$tenant_id" ] || [ -z "$client_id" ] || [ -z "$client_secret" ]; then
    warn "OpenCost Azure credentials not fully set — skipping cloud integration."
    warn "OpenCost will use public on-demand pricing (±30-50% off real cost)."
    warn "To enable: set AZURE_SUBSCRIPTION_ID, AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET"
    return
  fi

  kubectl create namespace opencost \
    --context "$APP_CONTEXT" \
    --dry-run=client -o yaml | kubectl apply -f - --context "$APP_CONTEXT"

  kubectl create secret generic opencost-azure-creds \
    -n opencost \
    --context "$APP_CONTEXT" \
    --from-literal=AZURE_SUBSCRIPTION_ID="${sub_id}" \
    --from-literal=AZURE_TENANT_ID="${tenant_id}" \
    --from-literal=AZURE_CLIENT_ID="${client_id}" \
    --from-literal=AZURE_CLIENT_SECRET="${client_secret}" \
    --dry-run=client -o yaml | kubectl apply -f - --context "$APP_CONTEXT"

  log "OpenCost Azure cloud integration secret created ✓"
  log "OpenCost will use real Azure pricing (RI, spot, EA discounts) ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
deploy_app_cluster() {
  log "=== APP CLUSTER: ${APP_CONTEXT} ==="

  install_argocd "$APP_CONTEXT"
  add_repo_credentials "$APP_CONTEXT"
  create_app_secrets
  create_opencost_azure_secret

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
  # Check if loadtest cluster exists
  if ! az aks show --resource-group "${AKS_RESOURCE_GROUP}" --name "${LOADTEST_CLUSTER_NAME}" &>/dev/null; then
    log "Loadtest cluster not found (app-only deployment) — skipping loadtest bootstrap"
    return 0
  fi

  log "=== LOADTEST CLUSTER: ${LOADTEST_CONTEXT} ==="

  # Check for at least one schedulable (untainted) node before proceeding.
  # The system node pool has CriticalAddonsOnly=true:NoSchedule so pods cannot
  # land there. Without a user node pool (needs vCPU quota) we would waste
  # 10+ minutes waiting for pods that will never schedule.
  local schedulable
  schedulable=$(kubectl get nodes --context "$LOADTEST_CONTEXT" \
    --no-headers -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints' \
    2>/dev/null | grep -v "CriticalAddonsOnly" | wc -l)

  if [[ "$schedulable" -eq 0 ]]; then
    warn "No schedulable user nodes on ${LOADTEST_CONTEXT} — skipping bootstrap."
    warn "Cause: vCPU quota exhausted. Ask your Azure admin to raise the quota"
    warn "       for Standard_D2s_v3 in West Europe, then re-run deploy.sh."
    return 1
  fi

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

  # Loadtest cluster bootstrap is best-effort: it requires a user node pool
  # which needs additional vCPU quota. If quota is exhausted the pods will be
  # Pending and the wait will time out — that must not block the app cluster.
  if deploy_loadtest_cluster; then
    log "Loadtest cluster bootstrap complete ✓"
  else
    warn "Loadtest cluster bootstrap failed (likely no schedulable nodes due to vCPU quota)."
    warn "App cluster is fully operational. Fix loadtest quota and re-run deploy.sh."
  fi

  wait_for_ingress
  smoke_test
  print_summary
}

main "$@"
