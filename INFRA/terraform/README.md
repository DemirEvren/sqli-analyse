# Shelfware — Terraform Infrastructure (AKS / Azure)

This directory contains the full Terraform infrastructure for deploying the Shelfware application to **Azure Kubernetes Service (AKS)**. The code is structured for multi-cloud extension (AWS, GCP) via variables and provider stubs.

---

## Directory structure

```
INFRA/terraform/
├── bootstrap/                    # ONE-TIME: creates Azure Blob state backend
│   ├── main.tf                   # Storage account + container + delete lock
│   ├── variables.tf
│   └── outputs.tf
│
├── modules/
│   ├── networking/               # VNet, subnets, NAT gateway, NSGs
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── aks/                      # Reusable AKS cluster (called twice)
│   │   ├── main.tf               # System pool + user pool, OIDC, RBAC, Kepler-ready
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── acr/                      # Azure Container Registry
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── monitoring/               # Log Analytics, AKS diagnostic settings
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── main.tf                       # Root: wires all modules + Kubernetes bootstrap resources
├── providers.tf                  # azurerm, azuread, kubernetes (×2), helm (×2)
├── versions.tf                   # required_providers + azurerm backend config
├── variables.tf                  # All input variables (cloud-agnostic structure)
├── terraform.tfvars              # Your values (copy & fill in)
├── outputs.tf                    # Cluster FQDNs, kubeconfig paths, ACR login server
├── bootstrap-aks.sh              # Post-apply: installs ArgoCD + deploys workloads
└── .gitignore
```

---

## Clusters created

| Cluster | AKS name | Mirrors | Node pools |
|---------|----------|---------|------------|
| App | `shelfware-app` | k3d `shelfware-app` (1 server + 2 agents) | system: 1×D2s_v3 + user: 2–5×D4s_v3 |
| Loadtest | `shelfware-loadtest` | k3d `shelfware-loadtest` (1 server + 2 agents) | system: 1×D2s_v3 |

Both clusters share the same VNet (different subnets) so Locust on the loadtest cluster can reach the ingress-nginx LoadBalancer IP of the app cluster over the VNet — exactly like k3d's `k3d-shared` Docker network.

---

## Remote state & locking

### Azure (active)

| Concept | Implementation |
|---------|----------------|
| State storage | Azure Blob Storage (`tfstate` container) |
| State locking | **Native blob lease** — no extra resource needed |
| Concurrent lock error | `"Error: Failed to lock state: state blob is already locked"` |
| Protection | `CanNotDelete` management lock on the storage account |
| Versioning | Blob versioning enabled (90-day retention) |

### AWS (reference — uncomment when extending)

```hcl
backend "s3" {
  bucket         = "<bucket-from-bootstrap>"
  key            = "shelfware/terraform.tfstate"
  region         = "eu-west-1"
  dynamodb_table = "<table-from-bootstrap>"   # ← the DynamoDB lock table
  encrypt        = true
}
```

### GCP (reference)

```hcl
backend "gcs" {
  bucket = "<bucket-from-bootstrap>"
  prefix = "shelfware/terraform"
  # GCS uses object locks natively — no separate table needed
}
```

---

## Step-by-step deployment

### Prerequisites

```bash
# Install tools
brew install terraform kubectl helm azure-cli jq  # macOS
# OR: see https://developer.hashicorp.com/terraform/downloads

# Login to Azure
az login
az account set --subscription "<your-subscription-id>"
```

### Step 1 — Bootstrap state backend (once per project)

```bash
cd INFRA/terraform/bootstrap
terraform init
terraform apply

# Copy the output values:
terraform output backend_config
```

### Step 2 — Configure the main backend

Edit `INFRA/terraform/versions.tf` and replace the placeholder values in the `backend "azurerm"` block with the output from step 1.

**Or** create `INFRA/terraform/backend.conf`:

```ini
resource_group_name  = "rg-shelfware-tfstate"
storage_account_name = "<output from step 1>"
container_name       = "tfstate"
key                  = "shelfware/terraform.tfstate"
```

Then init with: `terraform init -backend-config=backend.conf`

### Step 3 — Configure your variables

```bash
cp terraform.tfvars terraform.tfvars.local   # or edit terraform.tfvars directly

# Fill in:
#   azure_subscription_id = "..."
```

Set sensitive values via environment variables (do NOT put them in tfvars):

```bash
export TF_VAR_postgres_password="your-strong-password"
export TF_VAR_jwt_secret="your-jwt-secret"
export TF_VAR_github_token="ghp_your_pat_here"
```

### Step 4 — Plan & Apply

```bash
cd INFRA/terraform
terraform init   # or: terraform init -backend-config=backend.conf
terraform plan -out=tfplan
terraform apply tfplan
```

Expected time: **~10–15 minutes** (AKS cluster provisioning is the bottleneck).

### Step 5 — Bootstrap Kubernetes

```bash
# Export the merged kubeconfig (printed by terraform apply outputs)
export KUBECONFIG=$(pwd)/kubeconfigs/merged.yaml

# Set remaining env vars
export GITHUB_TOKEN="ghp_..."
export POSTGRES_PASSWORD="..."
export JWT_SECRET="..."

# Run bootstrap
./bootstrap-aks.sh
```

This script:
1. Installs ArgoCD on both clusters
2. Ensures all secrets (postgres, ghcr.io) exist in the right namespaces
3. Applies the ArgoCD root Application on each cluster
4. Waits for ingress IP and prints DNS instructions
5. Runs smoke tests (HTTP 200 on `/` and `/api/projects`)

### Step 6 — DNS

After the loadbalancer IP is assigned:

```bash
# /etc/hosts (local testing)
echo "<INGRESS_IP>  shelfware.local test.shelfware.local" | sudo tee -a /etc/hosts

# OR Azure DNS zone
az network dns record-set a add-record \
  --resource-group rg-shelfware-tfstate \
  --zone-name shelfware.example.com \
  --record-set-name '@' \
  --ipv4-address <INGRESS_IP>
```

---

## Verify

```bash
# Both clusters visible
kubectl config get-contexts

# App cluster: ArgoCD applications
kubectl get applications -n argocd --context shelfware-app

# App cluster: all pods
kubectl get pods -A --context shelfware-app

# Loadtest: Locust
kubectl get pods -n locust --context shelfware-loadtest

# Smoke test PROD
curl -H "Host: shelfware.local" http://<INGRESS_IP>/
curl -H "Host: shelfware.local" http://<INGRESS_IP>/api/projects

# Smoke test TEST
curl -H "Host: test.shelfware.local" http://<INGRESS_IP>/

# Port-forward Grafana
kubectl port-forward svc/monitoring-stack-grafana -n monitoring 3000:80 --context shelfware-app
# → http://localhost:3000  (admin / prom-operator)
```

---

## Teardown

```bash
cd INFRA/terraform

# Destroy Kubernetes bootstrap resources first (namespaces, secrets)
terraform destroy -target=kubernetes_namespace.prod_shelfware \
                  -target=kubernetes_namespace.test_shelfware \
                  -target=kubernetes_namespace.locust

# Destroy everything else
terraform destroy

# The bootstrap state backend is NOT destroyed by this command.
# To destroy it (careful — this deletes all state history):
cd bootstrap && terraform destroy
```

---

## Multi-cloud extension guide

### Adding AWS (EKS)

1. Uncomment the `aws` provider in `versions.tf` and `providers.tf`
2. Add EKS module call in `main.tf` behind `var.cloud_provider == "aws"` condition
3. Switch backend to S3 + DynamoDB (see bootstrap/main.tf for reference code)

### Adding GCP (GKE)

1. Uncomment the `google` provider in `versions.tf` and `providers.tf`
2. Add GKE module call in `main.tf`
3. Switch backend to GCS (see bootstrap/main.tf for reference code)

The `variables.tf` already contains `aws_region`, `gcp_project_id`, `gcp_region` variables ready to use.

---

## Security notes

- **Secrets** are never stored in `.tfvars` files — always via `TF_VAR_*` environment variables or a secrets manager
- **State file** contains sensitive data (kubeconfig, secrets). The Blob Storage account has:
  - Private access only (no public blob access)
  - TLS 1.2 minimum
  - ZRS replication
  - `CanNotDelete` management lock
  - 90-day soft delete
- **ACR** admin credentials are disabled — access via managed identity (`AcrPull` role on kubelet identity)
- **AKS** local accounts are kept enabled for the Terraform bootstrap only. For production, disable them and use `azure_active_directory_role_based_access_control` with group object IDs.
