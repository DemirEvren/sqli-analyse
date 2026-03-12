#!/usr/bin/env bash
# ─── destroy.sh ────────────────────────────────────────────────────────────────
# Destroy the main Shelfware infrastructure WITHOUT destroying the tfstate backend.
#
# This is safe because:
#   • The tfstate backend (storage account) is in the bootstrap resource group
#   • Only the main resource group (with AKS, databases, etc) is destroyed
#   • You can redeploy later using the same state
#
# Usage:
#   bash destroy.sh                    # interactive confirmation
#   bash destroy.sh --force            # skip confirmation (careful!)
#   bash destroy.sh --also-destroy-backend  # also destroy the tfstate backend
#
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ─── Colour helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

log()     { echo -e "${GREEN}[$(date '+%H:%M:%S')]${RESET} $*"; }
info()    { echo -e "${BLUE}  ▸${RESET} $*"; }
warn()    { echo -e "${YELLOW}  ⚠ $*${RESET}"; }
fail()    { echo -e "${RED}  ✗ ERROR: $*${RESET}" >&2; exit 1; }
section() { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${BLUE}  $*${RESET}"; \
            echo -e "${BOLD}${BLUE}══════════════════════════════════════════${RESET}"; }
ask()     { echo -en "${YELLOW}  ? $* ${RESET}"; }

# ─── Flags ────────────────────────────────────────────────────────────────────
FORCE=false
ALSO_DESTROY_BACKEND=false

for arg in "$@"; do
  case "$arg" in
    --force)                   FORCE=true ;;
    --also-destroy-backend)    ALSO_DESTROY_BACKEND=true ;;
    *) fail "Unknown argument: $arg. Valid flags: --force, --also-destroy-backend" ;;
  esac
done

# ─── Load secrets from secrets.env if it exists ────────────────────────────────
if [ -f "${SCRIPT_DIR}/secrets.env" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/secrets.env"
fi

# ─────────────────────────────────────────────────────────────────────────────
check_prereqs() {
  section "Checking prerequisites"

  local missing=()
  for cmd in az terraform jq; do
    if command -v "$cmd" >/dev/null 2>&1; then
      info "$cmd $(${cmd} --version 2>/dev/null | head -1 | tr -d '\n' || true)"
    else
      missing+=("$cmd")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    fail "Missing required tools: ${missing[*]}"
  fi

  # Terraform providers still need these even during destroy
  local missing_vars=()
  [[ -z "${TF_VAR_postgres_password:-}" ]] && missing_vars+=("TF_VAR_postgres_password")
  [[ -z "${TF_VAR_jwt_secret:-}" ]]        && missing_vars+=("TF_VAR_jwt_secret")
  if [ ${#missing_vars[@]} -gt 0 ]; then
    fail "Missing required env vars (needed by Terraform providers during destroy): ${missing_vars[*]}\n  Source your secrets first:  source secrets.env"
  fi

  log "All prerequisites satisfied ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
azure_login() {
  section "Azure login"

  if az account show >/dev/null 2>&1; then
    local current_sub
    current_sub=$(az account show --query "{name:name, id:id}" -o tsv 2>/dev/null | tr '\t' ' ')
    log "Already logged in: ${current_sub}"
  else
    log "Logging in to Azure..."
    az login
  fi

  # Use current subscription without prompting
  if [ -z "${AZURE_SUBSCRIPTION_ID:-}" ]; then
    AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  fi

  az account set --subscription "${AZURE_SUBSCRIPTION_ID}"
  log "Active subscription: $(az account show --query name -o tsv) (${AZURE_SUBSCRIPTION_ID})"
}

# ─────────────────────────────────────────────────────────────────────────────
load_tfvars() {
  section "Loading Terraform variables"

  if [ ! -f "${SCRIPT_DIR}/terraform.tfvars" ]; then
    fail "terraform.tfvars not found. Please run deploy.sh first to set up the infrastructure."
  fi

  # Extract the main resource group name and project
  PROJECT=$(grep -E '^\s*project\s*=' "${SCRIPT_DIR}/terraform.tfvars" | sed 's/.*=\s*"\([^"]*\)".*/\1/')
  ENVIRONMENT=$(grep -E '^\s*environment\s*=' "${SCRIPT_DIR}/terraform.tfvars" | sed 's/.*=\s*"\([^"]*\)".*/\1/')

  if [ -z "${PROJECT}" ] || [ -z "${ENVIRONMENT}" ]; then
    fail "Could not extract project or environment from terraform.tfvars"
  fi

  # Check for explicit override in tfvars first, otherwise use standard naming
  local explicit_rg
  explicit_rg=$(grep -E '^\s*azure_resource_group_name\s*=' "${SCRIPT_DIR}/terraform.tfvars" \
    | sed 's/.*=\s*"\([^"]*\)".*/\1/' | tr -d '[:space:]')
  if [ -n "${explicit_rg}" ]; then
    MAIN_RG="${explicit_rg}"
  else
    MAIN_RG="rg-${PROJECT}-${ENVIRONMENT}"
  fi
  BOOTSTRAP_RG="rg-${PROJECT}-tfstate"

  info "Project: ${PROJECT}"
  info "Environment: ${ENVIRONMENT}"
  info "Main RG to destroy: ${MAIN_RG}"
  info "Bootstrap RG (preserved): ${BOOTSTRAP_RG}"
}

# ─────────────────────────────────────────────────────────────────────────────
confirm_destroy() {
  section "⚠ Destroy Confirmation"
  echo ""
  warn "You are about to DESTROY the main infrastructure:"
  warn "  • AKS cluster"
  warn "  • PostgreSQL database"
  warn "  • All associated resources in: ${MAIN_RG}"
  echo ""
  info "The tfstate backend (${BOOTSTRAP_RG}) will be PRESERVED"
  info "You can redeploy using the same state file later."
  echo ""

  if [ "${FORCE}" = true ]; then
    log "Proceeding (--force flag set)"
    return 0
  fi

  ask "Type 'destroy' to confirm, or press Ctrl+C to abort: "
  read -r confirmation
  if [ "${confirmation}" != "destroy" ]; then
    log "Destruction aborted."
    exit 0
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
remove_argocd_finalizers() {
  section "Removing ArgoCD finalizers (prevents namespace hang on destroy)"

  local kubeconfig_app="${SCRIPT_DIR}/kubeconfigs/merged-admin.yaml"
  if [ ! -f "${kubeconfig_app}" ]; then
    warn "Admin kubeconfig not found — skipping ArgoCD finalizer cleanup"
    return 0
  fi

  export KUBECONFIG="${kubeconfig_app}"

  for ctx in shelfware-app shelfware-loadtest; do
    if kubectl cluster-info --context "${ctx}" >/dev/null 2>&1; then
      info "Removing Application finalizers on ${ctx}..."
      # Remove finalizers from all ArgoCD Applications so the namespace doesn't hang Terminating
      kubectl get applications -A --context "${ctx}" -o json 2>/dev/null \
        | python3 -c "
import json, sys, subprocess
data = json.load(sys.stdin)
for app in data.get('items', []):
    ns   = app['metadata']['namespace']
    name = app['metadata']['name']
    if app.get('metadata', {}).get('finalizers'):
        r = subprocess.run(
            ['kubectl', 'patch', 'application', name, '-n', ns,
             '--context', '${ctx}', '--type', 'json',
             '-p', '[{\"op\":\"remove\",\"path\":\"/metadata/finalizers\"}]'],
            capture_output=True)
        print(f'  Removed finalizers: {ns}/{name}')
" 2>/dev/null || true

      # Scale ArgoCD to zero so it stops reconciling while infra is torn down
      kubectl scale deployment -n argocd --all --replicas=0 --context "${ctx}" >/dev/null 2>&1 || true
      info "ArgoCD scaled down on ${ctx} ✓"
    else
      warn "${ctx} unreachable — skipping (cluster may already be gone)"
    fi
  done

  log "ArgoCD cleanup complete ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
destroy_main() {
  section "Initialising Terraform"

  cd "${SCRIPT_DIR}"

  if [ ! -f "${SCRIPT_DIR}/backend.conf" ]; then
    fail "backend.conf not found.\nRun deploy.sh once first, or create it manually with your storage account details."
  fi

  terraform init \
    -backend-config="${SCRIPT_DIR}/backend.conf" \
    -reconfigure \
    -input=false \
    >/dev/null \
    || fail "terraform init failed — check backend.conf and Azure credentials"
  log "Terraform init ✓"

  section "Destroying main infrastructure"
  info "Running: terraform destroy -auto-approve"
  echo ""

  terraform destroy -auto-approve || fail "Terraform destroy failed"

  log "Main infrastructure destroyed ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
destroy_backend() {
  section "Destroying tfstate backend"
  warn "This will DELETE the Terraform state file!"
  echo ""

  ask "Type 'destroy-backend' to confirm, or press Ctrl+C to abort: "
  read -r confirmation
  if [ "${confirmation}" != "destroy-backend" ]; then
    log "Backend destruction aborted."
    return 0
  fi

  cd "${SCRIPT_DIR}/bootstrap"
  terraform destroy -auto-approve || fail "Bootstrap terraform destroy failed"

  log "Backend destroyed ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo "╔══════════════════════════════════════════╗"
  echo "║     Shelfware AKS — Destroy Script       ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""

  check_prereqs
  azure_login
  load_tfvars
  confirm_destroy
  remove_argocd_finalizers
  destroy_main

  if [ "${ALSO_DESTROY_BACKEND}" = true ]; then
    destroy_backend
  else
    echo ""
    info "To also destroy the tfstate backend, run:"
    info "  bash destroy.sh --also-destroy-backend"
  fi

  echo ""
  log "Destroy complete!"
}

main "$@"
