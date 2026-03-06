#!/usr/bin/env bash
# ─── deploy.sh ────────────────────────────────────────────────────────────────
# Full end-to-end deployment: Azure infra + Kubernetes + ArgoCD + Shelfware + Locust.
#
# Usage:
#   bash deploy.sh                          # interactive — prompts for every value
#   bash deploy.sh --skip-bootstrap         # skip tfstate backend creation (already exists)
#   bash deploy.sh --skip-images            # skip Docker build/push (images already on ghcr.io)
#   bash deploy.sh --skip-bootstrap --skip-images
#   bash deploy.sh --destroy                # tear everything down
#
# All required values can also be pre-set as environment variables to run non-interactively:
#   AZURE_SUBSCRIPTION_ID, POSTGRES_PASSWORD, JWT_SECRET, GITHUB_TOKEN
#
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BOOTSTRAP_DIR="${SCRIPT_DIR}/bootstrap"

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
SKIP_BOOTSTRAP=false
SKIP_IMAGES=false
DESTROY=false

for arg in "$@"; do
  case "$arg" in
    --skip-bootstrap) SKIP_BOOTSTRAP=true ;;
    --skip-images)    SKIP_IMAGES=true ;;
    --destroy)        DESTROY=true ;;
    *) fail "Unknown argument: $arg. Valid flags: --skip-bootstrap, --skip-images, --destroy" ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────────────
check_prereqs() {
  section "Checking prerequisites"

  local missing=()
  for cmd in az terraform kubectl helm jq curl docker; do
    if command -v "$cmd" >/dev/null 2>&1; then
      info "$cmd $(${cmd} --version 2>/dev/null | head -1 | tr -d '\n' || true)"
    else
      missing+=("$cmd")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    fail "Missing required tools: ${missing[*]}
  Install guide:
    az        → https://docs.microsoft.com/cli/azure/install-azure-cli
    terraform → https://developer.hashicorp.com/terraform/install  (or: brew install terraform)
    kubectl   → https://kubernetes.io/docs/tasks/tools/
    helm      → https://helm.sh/docs/intro/install/
    jq        → brew install jq  /  apt install jq
    docker    → https://docs.docker.com/get-docker/"
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
    ask "Use this subscription? [Y/n]: "
    read -r ans
    if [[ "${ans,,}" == "n" ]]; then
      az login
    fi
  else
    log "Logging in to Azure..."
    az login
  fi

  # Resolve subscription
  if [ -z "${AZURE_SUBSCRIPTION_ID:-}" ]; then
    local current_id
    current_id=$(az account show --query id -o tsv)
    ask "Subscription ID [${current_id}]: "
    read -r input
    AZURE_SUBSCRIPTION_ID="${input:-${current_id}}"
  fi

  az account set --subscription "${AZURE_SUBSCRIPTION_ID}"
  log "Active subscription: $(az account show --query name -o tsv) (${AZURE_SUBSCRIPTION_ID})"
}

# ─────────────────────────────────────────────────────────────────────────────
collect_secrets() {
  section "Secrets"
  info "These are stored as Kubernetes Secrets (encrypted at rest in Azure). Never committed to Git."
  echo ""

  if [ -z "${POSTGRES_PASSWORD:-}" ]; then
    ask "Postgres password (min 16 chars): "
    read -rs POSTGRES_PASSWORD; echo ""
    export POSTGRES_PASSWORD
  else
    info "POSTGRES_PASSWORD already set in environment ✓"
  fi
  [ ${#POSTGRES_PASSWORD} -lt 16 ] && fail "POSTGRES_PASSWORD must be at least 16 characters"

  if [ -z "${JWT_SECRET:-}" ]; then
    ask "JWT secret (min 32 chars, or press Enter to auto-generate): "
    read -rs JWT_SECRET; echo ""
    if [ -z "${JWT_SECRET}" ]; then
      JWT_SECRET=$(openssl rand -hex 32)
      info "Auto-generated JWT secret ✓"
    fi
    export JWT_SECRET
  else
    info "JWT_SECRET already set in environment ✓"
  fi
  [ ${#JWT_SECRET} -lt 32 ] && fail "JWT_SECRET must be at least 32 characters"

  if [ -z "${GITHUB_TOKEN:-}" ]; then
    info "GitHub PAT needed to pull images from ghcr.io/demirevren/*"
    info "Create at: GitHub → Settings → Developer settings → Personal access tokens → Fine-grained"
    info "Required permission: read:packages (Contents: Read)"
    ask "GitHub token (ghp_...): "
    read -rs GITHUB_TOKEN; echo ""
    export GITHUB_TOKEN
  else
    info "GITHUB_TOKEN already set in environment ✓"
  fi
  [ -z "${GITHUB_TOKEN}" ] && fail "GITHUB_TOKEN is required"

  # Export as Terraform variables
  export TF_VAR_postgres_password="${POSTGRES_PASSWORD}"
  export TF_VAR_jwt_secret="${JWT_SECRET}"
  export TF_VAR_github_token="${GITHUB_TOKEN}"
}

# ─────────────────────────────────────────────────────────────────────────────
setup_tfvars() {
  section "Terraform variables"

  if [ ! -f "${SCRIPT_DIR}/terraform.tfvars" ]; then
    info "terraform.tfvars not found — creating from example template..."
    cp "${SCRIPT_DIR}/terraform.tfvars.example" "${SCRIPT_DIR}/terraform.tfvars"

    # Inject the subscription ID that was already confirmed
    sed -i "s|azure_subscription_id.*=.*\"\"|azure_subscription_id = \"${AZURE_SUBSCRIPTION_ID}\"|" \
      "${SCRIPT_DIR}/terraform.tfvars"

    info "Created terraform.tfvars with subscription_id = ${AZURE_SUBSCRIPTION_ID}"
    info "All other values use the defaults from terraform.tfvars.example (westeurope, D4s_v3, etc.)"
    info "Edit ${SCRIPT_DIR}/terraform.tfvars if you want to change regions or VM sizes."
  else
    info "terraform.tfvars already exists — using as-is"
    # Ensure subscription ID is set if it was empty
    if grep -q 'azure_subscription_id.*=.*""' "${SCRIPT_DIR}/terraform.tfvars"; then
      sed -i "s|azure_subscription_id.*=.*\"\"|azure_subscription_id = \"${AZURE_SUBSCRIPTION_ID}\"|" \
        "${SCRIPT_DIR}/terraform.tfvars"
      info "Patched azure_subscription_id in existing terraform.tfvars"
    fi
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
bootstrap_tfstate() {
  section "Step 0 — Bootstrapping remote state backend"

  if $SKIP_BOOTSTRAP; then
    info "Skipping bootstrap (--skip-bootstrap flag set)"
    # Still need to ensure backend.conf exists
    if [ ! -f "${SCRIPT_DIR}/backend.conf" ]; then
      fail "backend.conf not found. Either remove --skip-bootstrap or create backend.conf manually."
    fi
    return
  fi

  # Check if the tfstate resource group already exists (must be pre-created by admin)
  local tfstate_rg="rg-shelfware-tfstate"
  if ! az group show --name "${tfstate_rg}" >/dev/null 2>&1; then
    fail "Resource group '${tfstate_rg}' does not exist. Ask your Azure admin to create it and assign you Storage Account Contributor + Locks Contributor roles on it."
  fi

  # Check if already bootstrapped (storage account exists)
  local sa_name
  sa_name=$(az storage account list \
    --resource-group "${tfstate_rg}" \
    --query "[0].name" -o tsv 2>/dev/null || true)

  if [ -n "${sa_name}" ]; then
    warn "Resource group '${tfstate_rg}' already has storage account '${sa_name}' — backend was previously bootstrapped"
    write_backend_conf "${tfstate_rg}" "${sa_name}"
    return
  fi

  log "Creating tfstate backend (this takes ~1 minute)..."

  cd "${BOOTSTRAP_DIR}"
  terraform init -input=false
  terraform apply -auto-approve -input=false

  local sa_name
  sa_name=$(terraform output -raw storage_account_name)
  local rg_name
  rg_name=$(terraform output -raw resource_group_name)

  cd "${SCRIPT_DIR}"

  write_backend_conf "${rg_name}" "${sa_name}"
  log "State backend ready: ${sa_name} ✓"
}

write_backend_conf() {
  local rg="$1" sa="$2"
  cat > "${SCRIPT_DIR}/backend.conf" <<EOF
resource_group_name  = "${rg}"
storage_account_name = "${sa}"
container_name       = "tfstate"
key                  = "shelfware/terraform.tfstate"
EOF
  info "Written backend.conf → storage_account=${sa}"
}

# ─────────────────────────────────────────────────────────────────────────────
terraform_init() {
  section "Initialising Terraform"

  cd "${SCRIPT_DIR}"
  terraform init -backend-config=backend.conf -input=false -reconfigure
  log "Terraform init ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
push_images() {
  section "Step 4 — Checking / building Docker images"

  if $SKIP_IMAGES; then
    info "Skipping image build/push (--skip-images flag set)"
    return
  fi

  local backend_image="ghcr.io/demirevren/shelfware-backend:latest"
  local frontend_image="ghcr.io/demirevren/shelfware-frontend:latest"

  # Check if images already exist on ghcr.io
  log "Checking if images are already published..."
  echo "${GITHUB_TOKEN}" | docker login ghcr.io -u DemirEvren --password-stdin 2>/dev/null

  local need_build=false
  if docker manifest inspect "${backend_image}" >/dev/null 2>&1 && \
     docker manifest inspect "${frontend_image}" >/dev/null 2>&1; then
    info "Images already exist on ghcr.io ✓"
    ask "Re-build and push anyway? [y/N]: "
    read -r ans
    [[ "${ans,,}" == "y" ]] || { info "Skipping image build"; return; }
    need_build=true
  else
    warn "One or more images not found on ghcr.io — building now"
    need_build=true
  fi

  if $need_build; then
    local shelfware_dir="${REPO_ROOT}/shelfware"
    [ -d "${shelfware_dir}" ] || fail "shelfware source directory not found at ${shelfware_dir}"

    log "Building backend image..."
    docker build -t "${backend_image}" "${shelfware_dir}/backend"
    docker push "${backend_image}"
    log "Backend image pushed ✓"

    log "Building frontend image..."
    docker build -t "${frontend_image}" "${shelfware_dir}/frontend"
    docker push "${frontend_image}"
    log "Frontend image pushed ✓"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
terraform_apply() {
  section "Step 5 — Terraform apply (two-stage)"

  cd "${SCRIPT_DIR}"

  # ── Stage 1: Azure infrastructure ────────────────────────────────────────
  log "Stage 1/2: Creating Azure infrastructure (~15-20 min)..."
  info "VNet, NAT gateway, Log Analytics, AKS clusters (resource group must already exist)"

  terraform apply -auto-approve -input=false \
    -target=module.monitoring \
    -target=module.networking \
    -target=module.aks_app \
    -target=module.aks_loadtest

  log "Stage 1 complete ✓"

  # ── Stage 2: Kubernetes resources ────────────────────────────────────────
  log "Stage 2/2: Creating Kubernetes namespaces and secrets (~2 min)..."
  info "Namespaces: prod-shelfware, test-shelfware, argocd, locust"
  info "Secrets: postgres-secret, ghcr-credentials, argocd-repo-shelfware"

  terraform apply -auto-approve -input=false

  log "Stage 2 complete ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
export_kubeconfig() {
  section "Step 6 — Exporting kubeconfig"

  local merged="${SCRIPT_DIR}/kubeconfigs/merged.yaml"
  [ -f "${merged}" ] || fail "merged.yaml not found at ${merged}. Did terraform apply complete?"

  export KUBECONFIG="${merged}"
  log "KUBECONFIG=${merged}"

  # Verify connectivity
  log "Verifying cluster connectivity..."
  kubectl get nodes --context shelfware-app   --no-headers 2>/dev/null | \
    awk '{print "  shelfware-app   → node: "$1" ("$2")"}' || \
    warn "shelfware-app not yet reachable — may still be provisioning"

  kubectl get nodes --context shelfware-loadtest --no-headers 2>/dev/null | \
    awk '{print "  shelfware-loadtest → node: "$1" ("$2")"}' || \
    warn "shelfware-loadtest not yet reachable — may still be provisioning"
}

# ─────────────────────────────────────────────────────────────────────────────
run_bootstrap() {
  section "Step 7 — Bootstrapping ArgoCD + deploying Shelfware + Locust"

  export GITHUB_USERNAME="${GITHUB_USERNAME:-DemirEvren}"
  export GITHUB_REPO_URL="${GITHUB_REPO_URL:-https://github.com/DemirEvren/sqli-analyse.git}"

  cd "${SCRIPT_DIR}"
  bash bootstrap-aks.sh

  log "Bootstrap complete ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
print_final_summary() {
  section "Deployment complete 🎉"

  local merged="${SCRIPT_DIR}/kubeconfigs/merged.yaml"

  # Get ingress IP
  local ingress_ip=""
  ingress_ip=$(kubectl get svc ingress-nginx-controller \
    -n ingress-nginx --context shelfware-app \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

  # Get ArgoCD password
  local argocd_pass=""
  argocd_pass=$(kubectl get secret argocd-initial-admin-secret \
    -n argocd --context shelfware-app \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)

  echo ""
  echo -e "${BOLD}  KUBECONFIG:${RESET}"
  echo -e "    export KUBECONFIG=${merged}"
  echo ""

  if [ -n "${ingress_ip}" ]; then
    echo -e "${BOLD}  Add to /etc/hosts:${RESET}"
    echo -e "    ${ingress_ip}  shelfware.local test.shelfware.local"
    echo ""
    echo -e "${BOLD}  Application URLs:${RESET}"
    echo -e "    http://shelfware.local        → Shelfware PROD"
    echo -e "    http://test.shelfware.local   → Shelfware TEST"
  else
    warn "Ingress IP not yet assigned. Check: kubectl get svc -n ingress-nginx --context shelfware-app"
  fi

  echo ""
  echo -e "${BOLD}  Port-forwards (run each in a separate terminal):${RESET}"
  echo -e "    # ArgoCD UI (user: admin / pass below):"
  echo -e "    kubectl port-forward svc/argocd-server -n argocd 8080:443 --context shelfware-app"
  echo -e "    # → https://localhost:8080"
  if [ -n "${argocd_pass}" ]; then
    echo -e "    #   Password: ${argocd_pass}"
  fi
  echo ""
  echo -e "    # Grafana:"
  echo -e "    kubectl port-forward svc/monitoring-stack-grafana -n monitoring 3000:80 --context shelfware-app"
  echo -e "    # → http://localhost:3000  (admin / prom-operator)"
  echo ""
  echo -e "    # Prometheus:"
  echo -e "    kubectl port-forward svc/monitoring-stack-kube-prom-prometheus -n monitoring 9090:9090 --context shelfware-app"
  echo -e "    # → http://localhost:9090"
  echo ""
  echo -e "    # Locust:"
  echo -e "    kubectl port-forward svc/locust-master -n locust 8089:8089 --context shelfware-loadtest"
  echo -e "    # → http://localhost:8089"
  echo ""
  echo -e "${BOLD}  kanalyzer (run from the kanalyzer/ directory):${RESET}"
  echo -e "    export KUBECONFIG=${merged}"
  echo -e "    kubectl port-forward svc/monitoring-stack-kube-prom-prometheus -n monitoring 9090:9090 --context shelfware-app &"
  echo -e "    .venv/bin/kanalyzer --config kanalyzer.yaml multi-cluster pipeline --window 1h"
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
run_destroy() {
  section "DESTROY — tearing down all resources"

  warn "This will PERMANENTLY DELETE:"
  warn "  • Both AKS clusters (shelfware-app, shelfware-loadtest)"
  warn "  • ACR and all images stored in it"
  warn "  • VNet, NAT gateway, Log Analytics workspace"
  warn "  • Resource group rg-shelfware-prod and everything inside it"
  warn ""
  warn "The tfstate storage account (rg-shelfware-tfstate) is NOT destroyed."
  echo ""
  ask "Type 'yes' to confirm destruction: "
  read -r confirmation
  [ "${confirmation}" = "yes" ] || { info "Destruction cancelled."; exit 0; }

  cd "${SCRIPT_DIR}"

  # Ensure kubeconfig and TF vars are available
  if [ -f "${SCRIPT_DIR}/kubeconfigs/merged.yaml" ]; then
    export KUBECONFIG="${SCRIPT_DIR}/kubeconfigs/merged.yaml"
  fi

  log "Running terraform destroy..."
  terraform destroy -auto-approve -input=false

  log "All resources destroyed ✓"
}

# ─────────────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${BLUE}║    Shelfware AKS — Full Deploy Script    ║${RESET}"
  echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════╝${RESET}"
  echo ""

  if $DESTROY; then
    check_prereqs
    azure_login
    collect_secrets
    run_destroy
    exit 0
  fi

  check_prereqs
  azure_login
  collect_secrets
  setup_tfvars
  bootstrap_tfstate
  terraform_init
  push_images
  terraform_apply
  export_kubeconfig
  run_bootstrap
  print_final_summary
}

main "$@"
