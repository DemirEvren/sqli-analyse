# Terraform Infrastructure — Shelfware on AKS

**Manages:** Two AKS clusters, ACR, VNet, NAT gateway, Log Analytics, Kubernetes bootstrapping  
**Provider:** Azure (azurerm ~3.110)  
**State backend:** Azure Blob Storage (in a separate bootstrap resource group)  
**Terraform version:** ≥ 1.7.5

---

## ❓ Does Terraform deploy Shelfware and Locust automatically?

**Short answer: Yes — completely automatically**, with no manual kubectl commands needed after the
initial `terraform apply` + `bootstrap-aks.sh`. The deployment chain works like this:

```
terraform apply
    │
    ├─► Creates Azure infra: VNet, NAT GW, ACR, AKS clusters, Log Analytics
    │
    ├─► Creates Kubernetes namespaces: prod-shelfware, test-shelfware, argocd, locust
    │
    └─► Creates Kubernetes secrets: postgres-secret, ghcr-credentials, argocd-repo-shelfware
            │
            ▼
bash bootstrap-aks.sh
    │
    ├─► Installs ArgoCD on shelfware-app  ──► syncs appcluster/root-app.yaml
    │       │
    │       │   ArgoCD reads INFRA/argocd/applications/appcluster/*.yaml from Git
    │       ├─► wave -3: ingress-nginx        (LoadBalancer → public IP)
    │       ├─► wave -2: prometheus-operator
    │       ├─► wave -1: monitoring-stack     (Prometheus + Grafana + Kepler)
    │       ├─► wave  0: KEDA
    │       ├─► wave  1: shelfware-test       (INFRA/kustomize/shelfware/overlays/test)
    │       │               backend (ghcr.io/demirevren/shelfware-backend:latest)
    │       │               frontend (ghcr.io/demirevren/shelfware-frontend:latest)
    │       │               postgres StatefulSet
    │       └─► wave  2: shelfware-prod       (INFRA/kustomize/shelfware/overlays/prod)
    │
    └─► Installs ArgoCD on shelfware-loadtest ──► syncs loadtest/root-app.yaml
            │
            └─► INFRA/kustomize/locust/overlays/loadtest
                    Locust master + worker Deployments
```

**The apps run from `ghcr.io/demirevren/`** — so images must be pushed there before deploying.
See §5 "Pre-flight: push images" for the one command needed if they aren't already published.

**Comparison with your local workflow:**

| What you do locally | What happens on AKS (cloud) |
|---|---|
| `bash scripts/deploy-shelfware.sh` | ArgoCD syncs `INFRA/kustomize/shelfware/overlays/prod` automatically |
| `kubectl apply -k INFRA/kustomize/shelfware/overlays/test` | ArgoCD syncs `overlays/test` automatically |
| `bash scripts/deploy-locust.sh` | ArgoCD syncs `INFRA/kustomize/locust/overlays/loadtest` automatically |
| `kubectl port-forward ...` for Prometheus | Still needed (no public ingress for Prometheus) |
| kanalyzer `--config kanalyzer.yaml` locally | Run on your workstation with the merged kubeconfig |

---

## Table of Contents

1. [Architecture overview](#1-architecture-overview)  
2. [Directory layout](#2-directory-layout)  
3. [Prerequisites — what you must do first](#3-prerequisites--what-you-must-do-first)  
4. [Secrets and credentials reference](#4-secrets-and-credentials-reference)  
5. [First-time deployment (step-by-step)](#5-first-time-deployment-step-by-step)  
6. [Day-2 operations](#6-day-2-operations)  
7. [Module reference](#7-module-reference)  
8. [Variable reference](#8-variable-reference)  
9. [Design decisions and trade-offs](#9-design-decisions-and-trade-offs)  
10. [Known limitations](#10-known-limitations)  
11. [Bugs fixed during development](#11-bugs-fixed-during-development)  
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Architecture overview

```
Azure Subscription
└── rg-shelfware-prod
    ├── shelfware-vnet (10.0.0.0/16)
    │   ├── subnet-app      (10.0.1.0/24) ──► AKS: shelfware-app
    │   ├── subnet-loadtest (10.0.2.0/24) ──► AKS: shelfware-loadtest
    │   └── subnet-pe       (10.0.3.0/24)  (private endpoints)
    ├── NAT Gateway  ──► stable outbound IP (whitelist in external APIs)
    ├── ACR: shelfwareprodacr
    ├── Log Analytics Workspace
    │
    ├── AKS: shelfware-app
    │   ├── node pool: system (D2s_v3 × 1)   ← CriticalAddonsOnly taint
    │   └── node pool: user   (D4s_v3 × 2-5) ← autoscaler, all shelfware workloads
    │       Kubernetes namespaces (Terraform-managed):
    │         prod-shelfware, test-shelfware, argocd
    │       Kubernetes secrets (Terraform-managed):
    │         postgres-secret, ghcr-credentials, argocd-repo-shelfware
    │
    └── AKS: shelfware-loadtest
        └── node pool: system (D2s_v3 × 1)
            Kubernetes namespaces: locust, argocd
```

ArgoCD on **shelfware-app** deploys (via GitOps, sync-wave order):
- ingress-nginx → prometheus-operator → kube-prometheus-stack + Kepler → KEDA → shelfware (test + prod)

ArgoCD on **shelfware-loadtest** deploys Locust.

---

## 2. Directory layout

```
INFRA/terraform/
│
├── bootstrap/               ← Run ONCE to create the tfstate storage account
│   ├── main.tf              Storage account + container + CanNotDelete lock
│   ├── variables.tf
│   └── outputs.tf           Prints storage account name → paste into backend.conf
│
├── modules/
│   ├── networking/          VNet, 3 subnets, NSGs, NAT gateway
│   ├── aks/                 Single AKS cluster (called twice: app + loadtest)
│   ├── acr/                 Azure Container Registry
│   └── monitoring/          Log Analytics workspace
│
├── main.tf                  Root: wires all modules + Kubernetes resources
├── providers.tf             azurerm / kubernetes×2 / helm×2
├── versions.tf              required_providers + azurerm backend block
├── variables.tf             All input variables
├── outputs.tf               Cluster FQDNs, ACR server, kubeconfig paths
│
├── bootstrap-aks.sh         Post-apply script: installs ArgoCD + deploys workloads
│
├── terraform.tfvars         YOUR values (gitignored — never commit)
├── terraform.tfvars.example Template (safe to commit)
├── backend.conf             YOUR backend connection (gitignored)
├── backend.conf.example     Template (safe to commit)
│
├── kubeconfigs/             Written by terraform apply (gitignored)
│   ├── shelfware-app.yaml
│   ├── shelfware-loadtest.yaml
│   └── merged.yaml          ← export as KUBECONFIG
│
└── .gitignore
```

---

## 3. Prerequisites — what you must do first

### 3.1 Required tools (install on your workstation)

| Tool | Min version | Install |
|---|---|---|
| Terraform | 1.7.5 | `brew install terraform` / [tfenv](https://github.com/tfutils/tfenv) |
| Azure CLI | 2.60 | `brew install azure-cli` |
| kubectl | 1.30 | `brew install kubectl` |
| helm | 3.15 | `brew install helm` |
| jq | 1.6 | `brew install jq` |

### 3.2 Azure permissions

Your Azure identity needs the following roles on the **subscription**:

| Role | Why needed |
|---|---|
| `Contributor` | Create resource groups, VNet, AKS, ACR, Log Analytics |
| `User Access Administrator` | Assign `AcrPull` to AKS kubelet identity; assign `AKS Cluster Admin` to Terraform SP |

> **For CI/CD (GitHub Actions):** Create an Azure AD application with federated credentials  
> (OIDC — no stored secrets). See §3.4.

### 3.3 Local setup

```bash
# Log in to Azure
az login
az account set --subscription "<your-subscription-id>"

# Clone the repo
git clone https://github.com/DemirEvren/sqli-analyse.git
cd sqli-analyse/kubernetes-app/INFRA/terraform

# Copy and fill in your values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill in azure_subscription_id, cluster names, etc.
# DO NOT put postgres_password / jwt_secret / github_token in the file!
# Use environment variables instead (see §4)
```

### 3.4 GitHub Actions setup (CI/CD)

Create the federated identity (OIDC — no stored secrets):

```bash
# 1. Create an Azure AD application for Terraform
APP_ID=$(az ad app create --display-name "shelfware-terraform-ci" --query appId -o tsv)
SP_OID=$(az ad sp create --id $APP_ID --query id -o tsv)

# 2. Assign roles on the subscription
SUB_ID=$(az account show --query id -o tsv)
az role assignment create --assignee $SP_OID --role "Contributor"            --scope /subscriptions/$SUB_ID
az role assignment create --assignee $SP_OID --role "User Access Administrator" --scope /subscriptions/$SUB_ID

# 3. Create federated credential for GitHub Actions
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-actions",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:DemirEvren/sqli-analyse:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# 4. Store as GitHub secrets:
#   AZURE_CLIENT_ID      = $APP_ID
#   AZURE_TENANT_ID      = $(az account show --query tenantId -o tsv)
#   AZURE_SUBSCRIPTION_ID = $SUB_ID
```

Then add the remaining secrets to GitHub (Settings → Secrets → Actions):

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | App registration client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `TF_STATE_STORAGE_ACCOUNT` | Storage account name from bootstrap output |
| `POSTGRES_PASSWORD` | Postgres password (min 16 chars, alphanumeric) |
| `JWT_SECRET` | JWT signing secret (min 32 chars) |
| `GH_TOKEN` | GitHub PAT with `read:packages` scope |

---

## 4. Secrets and credentials reference

**Never put secrets in `terraform.tfvars`.** Pass them as environment variables:

```bash
export TF_VAR_postgres_password="your-strong-password-here"
export TF_VAR_jwt_secret="your-32-char-jwt-secret-here"
export TF_VAR_github_token="ghp_your_github_pat_here"
```

These map directly to `var.postgres_password`, `var.jwt_secret`, `var.github_token` in `variables.tf`.

**Where secrets end up:**
- `postgres-secret` → Kubernetes Secret in `prod-shelfware` and `test-shelfware` namespaces
- `ghcr-credentials` → `kubernetes.io/dockerconfigjson` secret in both namespaces
- `argocd-repo-shelfware` → ArgoCD repository secret in both `argocd` namespaces

> ⚠️ Terraform stores secrets in its state file. The state file is in Azure Blob Storage  
> (encrypted at rest). **Do not use `terraform show` or `terraform state pull` on shared terminals.**

---

## 5. First-time deployment

### TL;DR — one script does everything

```bash
cd kubernetes-app/INFRA/terraform
bash deploy.sh
```

The script walks you through the entire deployment interactively, prompting for secrets and
confirming each stage. It replaces all the manual steps below. Flags:

| Flag | What it skips |
|---|---|
| `--skip-bootstrap` | tfstate backend creation (already exists from a previous run) |
| `--skip-images` | Docker build/push (images already on ghcr.io) |
| `--destroy` | Tears everything down instead of deploying |

Pre-set environment variables to run non-interactively (CI/CD):
```bash
export AZURE_SUBSCRIPTION_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export POSTGRES_PASSWORD="your-strong-password-min-16-chars"
export JWT_SECRET="your-32-char-secret-here-xxxxxxxxxxx"
export GITHUB_TOKEN="ghp_your_pat_here"
bash deploy.sh --skip-images   # images already on ghcr.io
```

---

### Manual step-by-step reference

If you prefer to run each step individually, or need to resume a partial deployment,
the full sequence is documented below.

---

### Step 0 — Bootstrap the state backend (run ONCE per subscription, ever)

This creates the Azure storage account that holds `terraform.tfstate`.

```bash
cd kubernetes-app/INFRA/terraform/bootstrap

terraform init
terraform apply
# Type 'yes' when prompted

# Copy the storage account name from the output — you need it in Step 2:
terraform output storage_account_name
# → tfstateshlfXXXXXXXX   (random suffix)
```

---

### Step 1 — Log in to Azure

```bash
az login
# A browser window opens. After login, select the right subscription if you have several.

az account set --subscription "<your-subscription-id>"

# Confirm the correct subscription is active:
az account show --query "{name:name, id:id}" -o table
```

---

### Step 2 — Configure the remote backend

```bash
cd kubernetes-app/INFRA/terraform

cp backend.conf.example backend.conf
```

Edit `backend.conf` and replace `REPLACE_WITH_BOOTSTRAP_OUTPUT` with the storage account
name from Step 0. The file should look like:

```hcl
resource_group_name  = "rg-shelfware-tfstate"
storage_account_name = "tfstateshlfXXXXXXXX"
container_name       = "tfstate"
key                  = "shelfware/terraform.tfstate"
```

Then initialise Terraform with the backend:

```bash
terraform init -backend-config=backend.conf
```

---

### Step 3 — Fill in your tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and fill in at minimum:

```hcl
cloud_provider        = "azure"
azure_subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
azure_location        = "westeurope"
azure_location_secondary = "northeurope"

project     = "shelfware"
environment = "prod"

app_cluster_name      = "shelfware-app"
loadtest_cluster_name = "shelfware-loadtest"

argocd_repo_url  = "https://github.com/DemirEvren/sqli-analyse.git"
github_username  = "DemirEvren"
```

**Never** put passwords in this file. Export them as environment variables instead:

```bash
export TF_VAR_postgres_password="your-strong-password-min-16-chars"
export TF_VAR_jwt_secret="your-32-char-secret-here-xxxxxxxxxxx"
export TF_VAR_github_token="ghp_your_github_pat_with_read_packages"
```

> **Get a GitHub PAT:** GitHub → Settings → Developer settings → Personal access tokens  
> → Fine-grained token → Repository permissions: `read:packages` (Contents: Read)

---

### Step 4 — Pre-flight: verify images are published to ghcr.io

The kustomize overlays reference `ghcr.io/demirevren/shelfware-backend:latest` and
`ghcr.io/demirevren/shelfware-frontend:latest`. These must exist before ArgoCD tries to pull them.

```bash
# Check if the backend image already exists:
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $(echo -n $TF_VAR_github_token | base64 -w0)" \
  https://ghcr.io/v2/demirevren/shelfware-backend/manifests/latest
# 200 = exists, 404 = needs to be pushed
```

If the images are **not** published yet, build and push them from the shelfware source:

```bash
cd kubernetes-app/shelfware

# Log in to ghcr.io:
echo $TF_VAR_github_token | docker login ghcr.io -u DemirEvren --password-stdin

# Build and push backend:
docker build -t ghcr.io/demirevren/shelfware-backend:latest ./backend
docker push ghcr.io/demirevren/shelfware-backend:latest

# Build and push frontend:
docker build -t ghcr.io/demirevren/shelfware-frontend:latest ./frontend
docker push ghcr.io/demirevren/shelfware-frontend:latest
```

---

### Step 5 — Two-stage terraform apply

On the first apply the Kubernetes providers cannot connect (clusters don't exist yet).
Stage 1 creates only Azure resources; Stage 2 creates Kubernetes resources.

**Stage 1 — Azure infrastructure only (~15–20 minutes):**

```bash
cd kubernetes-app/INFRA/terraform

terraform apply \
  -target=azurerm_resource_group.main \
  -target=module.monitoring \
  -target=module.networking \
  -target=module.acr \
  -target=module.aks_app \
  -target=module.aks_loadtest
# Type 'yes' when prompted
```

This creates: resource group, VNet, subnets, NAT gateway, NSGs, ACR,
Log Analytics workspace, and both AKS clusters.

**Stage 2 — Kubernetes resources (~2 minutes):**

```bash
terraform apply
# Type 'yes' when prompted
```

This creates: namespaces (`prod-shelfware`, `test-shelfware`, `argocd`, `locust`),
secrets (`postgres-secret`, `ghcr-credentials`, `argocd-repo-shelfware`),
writes kubeconfig files to `kubeconfigs/`, and merges them.

---

### Step 6 — Export the kubeconfig

```bash
export KUBECONFIG=$(pwd)/kubeconfigs/merged.yaml

# Verify both clusters are visible:
kubectl config get-contexts
# NAME                    CLUSTER
# shelfware-app           shelfware-app
# shelfware-loadtest      shelfware-loadtest

# Quick connectivity check:
kubectl get nodes --context shelfware-app
kubectl get nodes --context shelfware-loadtest
```

---

### Step 7 — Run the bootstrap script (deploys ArgoCD + all apps)

This is the equivalent of your local `deploy-shelfware.sh` + `deploy-locust.sh`,
but for AKS. It installs ArgoCD on both clusters and fires the GitOps sync that
deploys everything.

```bash
cd kubernetes-app/INFRA/terraform

export GITHUB_TOKEN="$TF_VAR_github_token"
export POSTGRES_PASSWORD="$TF_VAR_postgres_password"
export JWT_SECRET="$TF_VAR_jwt_secret"
export GITHUB_USERNAME="DemirEvren"

bash bootstrap-aks.sh
```

The script automatically does:
1. Installs ArgoCD on `shelfware-app` and `shelfware-loadtest`
2. Applies `INFRA/argocd/applications/appcluster/root-app.yaml` — ArgoCD then syncs:
   - wave -3 → ingress-nginx (creates the public LoadBalancer IP)
   - wave -2 → prometheus-operator
   - wave -1 → monitoring-stack (Prometheus + Grafana + Kepler + Alertmanager)
   - wave  0 → KEDA
   - wave  1 → shelfware-test namespace (backend + frontend + postgres)
   - wave  2 → shelfware-prod namespace (backend + frontend + postgres)
3. Applies `INFRA/argocd/applications/loadtest/root-app.yaml` — ArgoCD syncs Locust
4. Waits for the ingress-nginx LoadBalancer IP (~5 minutes)
5. Runs HTTP smoke tests against `shelfware.local` (prod) and `test.shelfware.local` (test)
6. Prints all port-forward commands

---

### Step 8 — Verify everything is running

```bash
# Watch ArgoCD sync all Applications in real-time:
kubectl get applications -n argocd --context shelfware-app -w
# All should show SYNCED / Healthy within ~10 minutes

# Check shelfware pods:
kubectl get pods -n prod-shelfware --context shelfware-app
# NAME                      READY   STATUS    RESTARTS
# backend-XXXXXXX-XXXXX     1/1     Running   0
# frontend-XXXXXXX-XXXXX    1/1     Running   0
# postgres-0                1/1     Running   0

kubectl get pods -n test-shelfware --context shelfware-app
# Same structure for the test namespace

# Check Locust:
kubectl get pods -n locust --context shelfware-loadtest
# NAME                  READY   STATUS    RESTARTS
# locust-master-XXXXX   1/1     Running   0
# locust-worker-XXXXX   1/1     Running   0

# Get the public ingress IP:
kubectl get svc ingress-nginx-controller -n ingress-nginx --context shelfware-app
# EXTERNAL-IP will show the public Azure IP

# Get ArgoCD admin password:
kubectl get secret argocd-initial-admin-secret \
  -n argocd --context shelfware-app \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

---

### Step 9 — Access the UIs

Add to your `/etc/hosts` (replace `20.XXX.XXX.XXX` with the real ingress IP):

```
20.XXX.XXX.XXX  shelfware.local test.shelfware.local
```

Then open in a browser:

| URL | Service |
|---|---|
| `http://shelfware.local` | Shelfware **prod** frontend |
| `http://test.shelfware.local` | Shelfware **test** frontend |
| `https://localhost:8080` | ArgoCD UI (after port-forward below) |
| `http://localhost:3000` | Grafana (after port-forward below) |
| `http://localhost:9090` | Prometheus (after port-forward below) |
| `http://localhost:8089` | Locust load test UI (after port-forward below) |

**Port-forwards (run each in a separate terminal):**

```bash
# ArgoCD UI:
kubectl port-forward svc/argocd-server -n argocd 8080:443 --context shelfware-app
# → https://localhost:8080  user: admin  pass: (from Step 8)

# Grafana:
kubectl port-forward svc/monitoring-stack-grafana -n monitoring 3000:80 --context shelfware-app
# → http://localhost:3000  user: admin  pass: prom-operator

# Prometheus:
kubectl port-forward svc/monitoring-stack-kube-prom-prometheus -n monitoring 9090:9090 --context shelfware-app
# → http://localhost:9090

# Locust:
kubectl port-forward svc/locust-master -n locust 8089:8089 --context shelfware-loadtest
# → http://localhost:8089
```

---

### Step 10 — Run kanalyzer against the cloud clusters

Your kanalyzer config auto-discovers clusters from kubectl contexts.
With the merged kubeconfig exported it works exactly as locally:

```bash
cd kanalyzer

# Ensure KUBECONFIG points to the merged file:
export KUBECONFIG=/path/to/INFRA/terraform/kubeconfigs/merged.yaml

# Port-forward Prometheus first (kanalyzer needs it):
kubectl port-forward svc/monitoring-stack-kube-prom-prometheus \
  -n monitoring 9090:9090 --context shelfware-app &

# Run the pipeline:
.venv/bin/kanalyzer --config kanalyzer.yaml multi-cluster pipeline --window 1h
```

> The `shelfware-loadtest` context won't have Prometheus (Locust-only cluster) — same
> behaviour you already see locally. Only `shelfware-app` will be analysed.

---

## 6. Day-2 operations

### Tear down and rebuild

```bash
# Destroy everything (prompts for confirmation)
terraform destroy

# Or with the workflow_dispatch trigger in GitHub Actions:
# Action: destroy  (requires manual approval in GitHub Environments)
```

### Scale node pool manually

```bash
az aks nodepool scale \
  --resource-group rg-shelfware-prod \
  --cluster-name shelfware-app \
  --name user \
  --node-count 3
```

> Terraform ignores `node_count` changes via `lifecycle.ignore_changes` — the cluster  
> autoscaler manages this. Manual scaling is only needed to force a specific count  
> for testing.

### Update Kubernetes version

```bash
# AKS upgrades are intentionally outside Terraform (lifecycle.ignore_changes = [kubernetes_version])
az aks upgrade \
  --resource-group rg-shelfware-prod \
  --name shelfware-app \
  --kubernetes-version 1.31
```

### Rotate secrets

```bash
# Update the env var and re-apply:
export TF_VAR_postgres_password="new-password"
terraform apply -target=kubernetes_secret.postgres_prod -target=kubernetes_secret.postgres_test
```

### Push a new image to ACR

```bash
az acr login --name $(terraform output -raw acr_name)
docker tag shelfware-backend:latest $(terraform output -raw acr_login_server)/shelfware-backend:latest
docker push $(terraform output -raw acr_login_server)/shelfware-backend:latest
```

---

## 7. Module reference

### `modules/networking`

Creates the VNet and all network primitives.

| Resource | Purpose |
|---|---|
| `azurerm_virtual_network` | 10.0.0.0/16 VNet |
| `azurerm_subnet.app` | 10.0.1.0/24 — AKS app cluster nodes |
| `azurerm_subnet.loadtest` | 10.0.2.0/24 — AKS loadtest cluster nodes |
| `azurerm_subnet.private_endpoints` | 10.0.3.0/24 — future private endpoints (ACR, Key Vault). Network policies set to `"Disabled"` as required by Azure for PE subnets. |
| `azurerm_nat_gateway` | Stable outbound IP for both clusters. Avoids per-LB SNAT port exhaustion. |
| `azurerm_network_security_group.app` | Allows inbound 80/443 (ingress-nginx) + 9000 (AKS tunnel) |
| `azurerm_network_security_group.loadtest` | No inbound rules — loadtest cluster is internal only |

**Outputs:** `vnet_id`, `subnet_app_id`, `subnet_loadtest_id`, `subnet_pe_id`, `nat_public_ip`

---

### `modules/aks`

Creates a single AKS cluster. Called twice from `main.tf`:
- `module.aks_app` with `cluster_role = "app"` — gets both system + user node pools
- `module.aks_loadtest` with `cluster_role = "loadtest"` — gets system pool only

| Feature | Configuration | Reason |
|---|---|---|
| Network plugin | Azure CNI | Pods get real VNet IPs (same as k3d flat networking) |
| Network policy | Azure | Micro-segmentation between namespaces |
| Outbound type | `userAssignedNATGateway` | Reuses our pre-created NAT GW; avoids AKS creating its own LB |
| Node identity | `SystemAssigned` | Simpler than user-assigned; no pre-provisioning required |
| OIDC issuer | Enabled | Prerequisite for Workload Identity (pods as Azure principals) |
| Workload Identity | Enabled | Replaces pod service account / SP credential rotation |
| Key Vault provider | Enabled with rotation every 2 min | Allows mounting KV secrets as files |
| Upgrade channel | `patch` | Auto-applies 1.30.x → 1.30.y, never minor version jumps |
| Maintenance window | Sunday 00:00–04:00 UTC | 4 consecutive 1-hour windows (`hours = [0,1,2,3]`) |
| Azure RBAC | Enabled | `kubectl` is gated by Azure AD (no static kubeconfig accounts) |
| Local account | Left enabled | Required for Terraform bootstrap; disable after first apply if desired |

**Node pool sizing — why these VM sizes:**

| Pool | VM | vCPU | RAM | k3d equivalent |
|---|---|---|---|---|
| system | D2s_v3 | 2 | 8 GiB | k3d server node |
| user (app) | D4s_v3 × 2–5 | 4 | 16 GiB | k3d agent nodes (8 vCPU / 22.8 GiB each) |
| system (loadtest) | D2s_v3 | 2 | 8 GiB | k3d server node |

**Outputs:** `cluster_id`, `cluster_name`, `cluster_fqdn`, `kube_config_raw` (sensitive),  
`kube_config` (sensitive), `kubeconfig_path`, `kubelet_identity_object_id`, `oidc_issuer_url`

---

### `modules/acr`

Azure Container Registry with optional geo-replication.

| Setting | Value | Reason |
|---|---|---|
| SKU | Premium | Required for geo-replication, quarantine scan, private link |
| Admin enabled | false | Use RBAC + managed identity only |
| Quarantine policy | true (Premium) | Blocks unscanned images from being pulled |
| Retention | 7 days | Soft-delete safety net against accidental tag deletion |
| AcrPull role | Assigned to kubelet MI | Nodes can pull without embedded credentials |

---

### `modules/monitoring`

Azure-side Log Analytics workspace only. In-cluster monitoring  
(Prometheus, Grafana, Kepler, Alertmanager) is deployed by ArgoCD via  
`INFRA/monitoring/kustomize`.

> **Why is the monitoring module so thin?**  
> The AKS diagnostic settings live in `main.tf` (as standalone `azurerm_monitor_diagnostic_setting`  
> resources), not inside this module. This is intentional: if they were inside the module,  
> a circular dependency would form — monitoring would need the cluster IDs (from the AKS  
> module) while AKS needs the workspace ID (from the monitoring module). See §11.

---

## 8. Variable reference

| Variable | Default | Required | Description |
|---|---|---|---|
| `cloud_provider` | — | ✅ | `"azure"` (stubs for `"aws"` / `"gcp"` in providers.tf) |
| `azure_subscription_id` | `""` | ✅ | Your Azure subscription GUID |
| `azure_location` | — | ✅ | Primary region, e.g. `"westeurope"` |
| `azure_location_secondary` | — | ✅ | For ACR geo-replication, e.g. `"northeurope"` |
| `azure_resource_group_name` | `""` | ❌ | Auto-generated as `rg-<project>-<env>` if empty |
| `project` | — | ✅ | e.g. `"shelfware"` — used in all resource names |
| `environment` | — | ✅ | e.g. `"prod"` |
| `tags` | `{}` | ❌ | Merged with default tags (`managed-by=terraform`, etc.) |
| `app_cluster_name` | — | ✅ | AKS cluster name for app workloads |
| `app_cluster_kubernetes_version` | `"1.30"` | ❌ | Initial K8s version (ignored after first apply) |
| `app_cluster_system_node_count` | `1` | ❌ | System pool fixed node count |
| `app_cluster_system_node_vm_size` | `"Standard_D2s_v3"` | ❌ | |
| `app_cluster_user_node_min` | `2` | ❌ | User pool autoscaler min |
| `app_cluster_user_node_max` | `5` | ❌ | User pool autoscaler max |
| `app_cluster_user_node_vm_size` | `"Standard_D4s_v3"` | ❌ | |
| `loadtest_cluster_name` | — | ✅ | AKS cluster name for Locust |
| `loadtest_cluster_kubernetes_version` | `"1.30"` | ❌ | |
| `loadtest_cluster_node_count` | `1` | ❌ | |
| `loadtest_cluster_node_vm_size` | `"Standard_D2s_v3"` | ❌ | |
| `acr_sku` | `"Premium"` | ❌ | `"Basic"` / `"Standard"` / `"Premium"` |
| `acr_geo_replication_enabled` | `false` | ❌ | Enable for multi-region production |
| `log_analytics_retention_days` | `30` | ❌ | Max 730 for compliance |
| `argocd_repo_url` | — | ✅ | Git repo URL for ArgoCD Applications |
| `argocd_target_revision` | `"main"` | ❌ | Git branch/tag |
| `github_username` | — | ✅ | For ghcr.io image pulls |
| `postgres_password` | — | ✅ | **Pass via `TF_VAR_postgres_password` env var** |
| `jwt_secret` | — | ✅ | **Pass via `TF_VAR_jwt_secret` env var** |
| `github_token` | — | ✅ | **Pass via `TF_VAR_github_token` env var** |
| `vnet_address_space` | `["10.0.0.0/16"]` | ❌ | |
| `subnet_app_cidr` | `"10.0.1.0/24"` | ❌ | Must not overlap `service_cidr` |
| `subnet_loadtest_cidr` | `"10.0.2.0/24"` | ❌ | |
| `subnet_private_endpoints_cidr` | `"10.0.3.0/24"` | ❌ | |

---

## 9. Design decisions and trade-offs

### Two-stage apply (instead of depends_on on providers)

Terraform provider configurations are evaluated before resource planning. When the  
`kubernetes` provider's `host` depends on a not-yet-created AKS cluster, Terraform cannot  
plan Kubernetes resources on the first run. The `try()` wrapper in `providers.tf` prevents  
a hard error on subsequent runs (when state exists) but does not help on a fresh workspace.

**Decision:** Accept the two-stage apply requirement and make it explicit in the docs and  
in `bootstrap-aks.sh` (which runs stages automatically).

**Alternative considered:** Use separate `terraform` workspaces — one for Azure infra, one for  
Kubernetes resources. Rejected because it adds operational complexity without reducing the  
two-apply requirement.

### Diagnostic settings in `main.tf`, not in the monitoring module

Keeping them in the monitoring module would create a module-level circular dependency  
(monitoring needs cluster IDs → AKS needs workspace ID). Terraform detects module cycles  
even when individual resources have no cycle. Putting the diagnostic settings in `main.tf`  
breaks the cycle while keeping the module reusable.

### NAT Gateway instead of per-cluster LoadBalancer SNAT

AKS default outbound type (`loadBalancer`) creates a Standard LB per cluster and allocates  
SNAT ports from a shared pool. Under burst traffic, SNAT exhaustion causes intermittent  
connection failures. A NAT Gateway provides 64,000 SNAT ports per public IP address and  
gives a stable IP for allowlisting in external services (ghcr.io, Electricity Maps API).

### System + user node pool split

Mirrors the k3d architecture (server node = system-only taint, agent nodes = user workloads).  
Benefits on AKS:
- Upgrading the system pool does not evict user workloads
- System pool VM size can be smaller (D2s_v3) than user pool (D4s_v3)
- Cost attribution is cleaner for chargeback

### `lifecycle.ignore_changes` on `kubernetes_version` and `node_count`

AKS Kubernetes upgrades are a long-running operation best managed via `az aks upgrade` or  
the Azure portal (with pre-upgrade checks). Letting Terraform manage `kubernetes_version`  
risks accidental in-place upgrades when the variable changes. Node count is managed by the  
cluster autoscaler at runtime — Terraform must not override it.

---

## 10. Known limitations

### 10.1 First-apply two-stage requirement (Action required by you)

Every fresh workspace needs the two-stage apply described in §5, Step 3.  
The `bootstrap-aks.sh` and the GitHub Actions workflow both handle this automatically.  
**If you run `terraform apply` with no targets on an empty state, the Kubernetes resources  
will fail to plan** because the clusters do not exist yet.

### 10.2 Terraform state holds Kubernetes secrets (Action required by you)

`postgres-secret` and `ghcr-credentials` are stored in Terraform state in plaintext  
(base64-encoded, not encrypted by Terraform). The state file is encrypted at rest in  
Azure Blob Storage but is readable by anyone with `Storage Blob Data Reader` on the  
container.

**Recommended mitigations:**
1. Restrict the tfstate container to the Terraform SP and a break-glass admin only.
2. After the initial deployment, consider moving secret management to Azure Key Vault  
   (the Key Vault Secrets Provider addon is already installed on the clusters).
3. Rotate secrets via `terraform apply -target=kubernetes_secret.*` rather than  
   via the Kubernetes API directly, so state stays in sync.

### 10.3 ACR `quarantine_policy_enabled` requires Premium SKU

If you downgrade `acr_sku` to `"Standard"` or `"Basic"`, Terraform will fail because  
`quarantine_policy_enabled = true` is only valid on Premium. Change to `false` before  
downgrading, or add a conditional (the `var.sku == "Premium" ? true : false` expression  
is already in `modules/acr/main.tf`).

### 10.4 `automatic_channel_upgrade = "patch"` interacts with `lifecycle.ignore_changes`

The `patch` channel auto-upgrades the cluster outside Terraform (via Azure's weekly  
maintenance window). This can cause the Terraform state to show a drift on  
`kubernetes_version` — but since `kubernetes_version` is in `ignore_changes`, Terraform  
will never try to revert it. This is the intended behavior.

### 10.5 Maintenance window is not a continuous block

`maintenance_window.allowed.hours = [0, 1, 2, 3]` means four **separate** 1-hour start  
windows (00:00–01:00, 01:00–02:00, 02:00–03:00, 03:00–04:00). From an operational  
perspective this is a continuous 4-hour block, but AKS internally treats each hour  
independently. A long upgrade operation that starts at 03:55 may run past 04:00.

### 10.6 Azure CNI IP exhaustion risk

With Azure CNI, each pod consumes a VNet IP from the node subnet.  
`subnet_app_cidr = "10.0.1.0/24"` gives 251 usable IPs. With `max_pods = 50` per node  
and up to 5 user nodes, maximum pod density is 250 pods — exactly at the subnet limit.  
If you expect more pods, widen the CIDR (e.g. `10.0.1.0/23` = 507 IPs) before deploying.

### 10.7 `local_account_disabled = false` leaves a credential surface

The local admin account is kept enabled so Terraform's bootstrap (and CI) can install  
ArgoCD using the `kube_config_raw` credential. For hardened production deployments,  
disable it after the first successful bootstrap:

```bash
az aks update \
  --resource-group rg-shelfware-prod \
  --name shelfware-app \
  --disable-local-accounts
```

Then remove `local_account_disabled = false` from the module variable and add  
`local_account_disabled = true` to prevent Terraform from re-enabling it.

### 10.8 GitHub Actions `apply` uses a saved plan from `plan` job

The plan artifact has a 5-day retention. If more than 5 days pass between the PR being  
merged and the apply job running, the artifact will be gone and the apply will fail.  
Re-trigger the workflow with `workflow_dispatch → apply` in that case.

---

## 11. Bugs fixed during development

These issues were found and corrected during the initial build. They are documented  
here so you understand what to watch for if you fork or modify this code.

| # | File | Bug | Impact | Fix applied |
|---|---|---|---|---|
| 1 | `main.tf` ↔ `modules/monitoring` | **Circular module dependency**: `monitoring` took `aks.cluster_id` as input while `aks` took `monitoring.workspace_id` — Terraform reports a cycle and refuses to plan | ❌ Breaks `terraform plan` completely | Moved `azurerm_monitor_diagnostic_setting` resources out of the monitoring module into `main.tf` as standalone resources |
| 2 | `modules/networking/main.tf` | `private_endpoint_network_policies_enabled = true` — **semantically wrong** (Azure requires this to be Disabled on PE subnets) AND the attribute was renamed in azurerm 3.84 to `private_endpoint_network_policies` (string) | ❌ Private endpoints would fail to resolve | Changed to `private_endpoint_network_policies = "Disabled"` |
| 3 | `modules/aks/main.tf` | `enable_auto_scaling = true` — **deprecated** since azurerm 3.84; renamed to `auto_scaling_enabled` | ⚠️ Deprecation warning today, breaking change in azurerm 4.x | Changed to `auto_scaling_enabled = true` |
| 4 | `modules/aks/main.tf` | `maintenance_window hours = [0, 4]` — **semantic bug**: this means two separate 1-hour windows (midnight and 4am), not a continuous block from 00:00 to 04:00 | ⚠️ Maintenance window was 2 hours shorter than intended | Changed to `hours = [0, 1, 2, 3]` |
| 5 | `main.tf` | `data "azurerm_subscription" "current"` — declared but never referenced | 🔵 Dead code | Removed |
| 6 | `modules/aks/main.tf` | `local.cluster_fqdn` — constructed manually but the output used `azurerm_kubernetes_cluster.main.fqdn` (the real attribute) anyway | 🔵 Dead code | Removed |
| 7 | `main.tf` | ArgoCD repository secret had different names on app (`"private-repo-creds"`) vs loadtest (`"repo-creds"`) clusters | 🔵 Inconsistency, confusing to operate | Both renamed to `"argocd-repo-shelfware"` |
| 8 | `bootstrap-aks.sh` | `${var.dns_zone_name:-<your-zone>}` — Terraform interpolation syntax inside a bash `echo` string | ❌ Script would have printed literal Terraform syntax | Changed to plain shell text |

---

## 12. Troubleshooting

### `Error: Cycle: module.monitoring, module.aks_app`

This means a version of the code still has the circular dependency (Bug #1).  
Confirm `modules/monitoring/variables.tf` has no `app_cluster_id` variable  
and that `main.tf` passes no `app_cluster_id` to the monitoring module call.

### `Error: expected "host" to not be empty`

The `kubernetes` provider tried to connect before the AKS cluster existed.  
Run the **two-stage apply** as described in §5 Step 3.

### `Error: Private endpoint creation failed — NetworkPoliciesAreNotDisabled`

The PE subnet still has `private_endpoint_network_policies_enabled = true` (old attribute).  
Ensure the subnet uses `private_endpoint_network_policies = "Disabled"` (Bug #2 fix).

### `helm_release` or `kubernetes_*` resources fail on plan

This is the two-stage apply limitation (§10.1). Run Stage 1 first to create  
the clusters, then run `terraform apply` again for the Kubernetes resources.

### `Error: The provided subscription_id is invalid`

`azure_subscription_id` is empty in `terraform.tfvars`.  
Fill it in or set `ARM_SUBSCRIPTION_ID` as an environment variable.

### Prometheus/kube-state-metrics not scraping nodes

This is a known k3d observation from the kanalyzer output (`Collected 0 nodes`).  
On AKS, kube-state-metrics runs on the user node pool and scrapes node metrics  
correctly. The fallback to the Kubernetes API (used in k3d) is still available  
as a safety net in kanalyzer.

### `az acr login` fails after ACR creation

ACR token provisioning takes ~30 seconds after the resource is created.  
Wait 60 seconds and retry. Or use the Terraform output:

```bash
terraform output -raw acr_login_server   # e.g. shelfwareprodacr.azurecr.io
az acr login --name $(terraform output -raw acr_name)
```
