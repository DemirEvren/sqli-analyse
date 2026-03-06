# Shelfware + kanalyzer — Deployment Guide

> **Versie:** 4 maart 2026 · **Taal:** Nederlands · **OS:** Fedora Linux / Windows (WSL2)

---

## Inhoudsopgave

1. [Overzicht](#1-overzicht)
2. [Vereisten (prerequisites)](#2-vereisten)
3. [Azure — wat de admin moet doen (eenmalig)](#3-azure--wat-de-admin-moet-doen-eenmalig)
4. [Secrets instellen](#4-secrets-instellen)
5. [Stap 1 — Terraform bootstrap (remote state)](#5-stap-1--terraform-bootstrap)
6. [Stap 2 — Terraform apply (Azure infra)](#6-stap-2--terraform-apply)
7. [Stap 3 — ArgoCD bootstrap](#7-stap-3--argocd-bootstrap)
8. [Stap 4 — Verificatie](#8-stap-4--verificatie)
9. [Stap 5 — kanalyzer installeren en configureren](#9-stap-5--kanalyzer-installeren)
10. [Stap 6 — kanalyzer draaien](#10-stap-6--kanalyzer-draaien)
11. [Secrets: waar staat wat?](#11-secrets-overzicht)
12. [GitLab CI/CD secrets](#12-gitlab-cicd-secrets)
13. [Troubleshooting](#13-troubleshooting)
14. [Destroy (opruimen)](#14-destroy)

---

## 1. Overzicht

```
┌─────────────────────────────────────────────────────────────────┐
│  Wat wordt er gedeployed?                                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Azure (Terraform)                                              │
│  ├── Resource Group (pre-created door admin)                    │
│  ├── Log Analytics Workspace (Container Insights)               │
│  ├── VNet + 3 subnets + NSGs + NAT Gateway                     │
│  ├── AKS cluster: shelfware-app                                 │
│  │   ├── namespaces: prod-shelfware, test-shelfware, argocd    │
│  │   ├── secrets: postgres-secret, ghcr-credentials, argocd    │
│  │   └── ArgoCD → deployt alle workloads via GitOps             │
│  └── AKS cluster: shelfware-loadtest                            │
│      ├── namespace: locust, argocd                              │
│      └── ArgoCD → deployt Locust load-test                      │
│                                                                 │
│  kanalyzer (Python CLI — draait lokaal of in CI)                │
│  ├── Analyseert AKS clusters op kosten / verspilling            │
│  ├── Genereert HTML-rapporten + Teams-alerts                    │
│  └── Draait dagelijks via GitLab CI/CD pipeline                 │
│                                                                 │
│  Container images: ghcr.io (GitHub Container Registry)          │
│  Geen ACR nodig — images worden gepulled via ghcr-credentials   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Vereisten

### Tools installeren

| Tool | Fedora | Windows (WSL2 / Ubuntu) |
|---|---|---|
| **Azure CLI** | `sudo dnf install azure-cli` | `curl -sL https://aka.ms/InstallAzureCLIDeb \| sudo bash` |
| **Terraform** | `sudo dnf install -y dnf-plugins-core && sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo && sudo dnf install terraform` | `sudo apt update && sudo apt install -y gnupg software-properties-common && wget -O- https://apt.releases.hashicorp.com/gpg \| sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \| sudo tee /etc/apt/sources.list.d/hashicorp.list && sudo apt update && sudo apt install terraform` |
| **kubectl** | `sudo dnf install kubernetes-client` | `sudo snap install kubectl --classic` |
| **Helm** | `sudo dnf install helm` | `sudo snap install helm --classic` |
| **jq** | `sudo dnf install jq` | `sudo apt install jq` |
| **Docker** | `sudo dnf install docker && sudo systemctl enable --now docker` | Docker Desktop (WSL2 backend) |
| **Python 3.10+** | `sudo dnf install python3.12` | `sudo apt install python3.12 python3.12-venv` |
| **Git** | `sudo dnf install git` | `sudo apt install git` |

### Verificatie (beide OS'en)

```bash
az version && terraform --version && kubectl version --client && helm version && jq --version && python3 --version
```

### Azure login

```bash
az login
az account set --subscription "<jouw-subscription-id>"
az account show    # check: juiste subscription?
```

---

## 3. Azure — wat de admin moet doen (eenmalig)

> ⚠ **Dit moet de Azure admin doen VOORDAT je Terraform draait.**
> Terraform kan géén resource groups aanmaken met de beperkte rollen.

### 3.1 Resource groups aanmaken

```bash
# De admin draait dit (of via Azure Portal):
az group create --name rg-shelfware-tfstate --location westeurope
az group create --name rg-shelfware-prod    --location westeurope
```

### 3.2 Rollen toekennen

Vervang `<deployer-object-id>` met het Object ID van je Azure AD user of service principal:

```bash
# Zoek je Object ID:
az ad signed-in-user show --query id -o tsv

DEPLOYER_ID="<deployer-object-id>"
```

**Op de tfstate resource group:**

```bash
# Storage Account Contributor — beheer storage account voor Terraform state
az role assignment create \
  --assignee "$DEPLOYER_ID" \
  --role "17d1049b-9a84-46fb-8f53-869881c3d3ab" \
  --scope "/subscriptions/<sub-id>/resourceGroups/rg-shelfware-tfstate"

# Locks Contributor — CanNotDelete lock op de state storage
az role assignment create \
  --assignee "$DEPLOYER_ID" \
  --role "28bf596f-4eb7-45ce-b5bc-6cf482fec137" \
  --scope "/subscriptions/<sub-id>/resourceGroups/rg-shelfware-tfstate"
```

**Op de main infra resource group:**

```bash
# Network Contributor — VNet/subnets/NSG/NAT/Public IP
az role assignment create \
  --assignee "$DEPLOYER_ID" \
  --role "4d97b98b-1d4f-4787-a291-c67834d212e7" \
  --scope "/subscriptions/<sub-id>/resourceGroups/rg-shelfware-prod"

# Azure Kubernetes Service Contributor Role — AKS clusters + node pools
az role assignment create \
  --assignee "$DEPLOYER_ID" \
  --role "ed7f3fbd-7b88-4dd4-9017-9adb7ce333f8" \
  --scope "/subscriptions/<sub-id>/resourceGroups/rg-shelfware-prod"

# Log Analytics Contributor — Log Analytics workspace
az role assignment create \
  --assignee "$DEPLOYER_ID" \
  --role "92aaf0da-9dab-42b6-94a3-d43ce8d16293" \
  --scope "/subscriptions/<sub-id>/resourceGroups/rg-shelfware-prod"

# Monitoring Contributor — Diagnostic Settings
az role assignment create \
  --assignee "$DEPLOYER_ID" \
  --role "749f88d5-cbae-40b8-bcfc-e573ddc772fa" \
  --scope "/subscriptions/<sub-id>/resourceGroups/rg-shelfware-prod"
```

### 3.3 OpenCost Azure Cloud Integration (optioneel, aanbevolen)

> Dit geeft OpenCost toegang tot de **echte** Azure-prijzen per VM-type
> (inclusief RI, spot, EA-kortingen), zodat kostenverdeling per namespace/workload
> accuraat is — niet alleen het totaal.

De admin moet een **Cost Management Reader** rol toekennen op subscription-niveau:

```bash
# Cost Management Reader — op de SUBSCRIPTION (niet op RG)
# Dit geeft read-only toegang tot de Azure Billing Rate Card API
az role assignment create \
  --assignee "$DEPLOYER_ID" \
  --role "72fafb9e-0641-4937-9268-a91bfd8191a3" \
  --scope "/subscriptions/<sub-id>"
```

> ℹ Dit is een **read-only** rol — het kan geen resources wijzigen, alleen prijzen opvragen.

De deployer moet deze env vars zetten in `secrets.env` (naast de bestaande):

```bash
# OpenCost Azure Cloud Integration (optioneel)
export AZURE_SUBSCRIPTION_ID="<subscription-id>"
export AZURE_TENANT_ID="<tenant-id>"
export AZURE_CLIENT_ID="<client-id>"       # kan dezelfde SP zijn als Terraform
export AZURE_CLIENT_SECRET="<client-secret>"
```

Het `bootstrap-aks.sh` script maakt automatisch een Kubernetes Secret aan
(`opencost-azure-creds` in namespace `opencost`) met deze waarden. Als de
env vars niet gezet zijn, wordt de cloud integration overgeslagen en gebruikt
OpenCost publieke on-demand prijzen.

### 3.4 Verificatie (deployer checkt zelf)

```bash
# Controleer dat je de juiste rollen hebt:
az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv)" \
  --scope "/subscriptions/<sub-id>/resourceGroups/rg-shelfware-prod" \
  --output table

# Moet tonen: Network Contributor, Azure Kubernetes Service Contributor Role,
# Log Analytics Contributor, Monitoring Contributor
```

---

## 4. Secrets instellen

### Strategie: environment variables + `.env` file

Secrets staan **nergens in Git**. Ze worden doorgegeven via environment variables:

| Secret | Terraform var | Env var | Waar nodig |
|---|---|---|---|
| PostgreSQL wachtwoord | `postgres_password` | `TF_VAR_postgres_password` | K8s secret → backend pods |
| JWT signing key | `jwt_secret` | `TF_VAR_jwt_secret` | K8s secret → backend pods |
| GitHub PAT (ghcr.io) | `github_token` | `TF_VAR_github_token` | K8s imagePullSecret |
| Azure subscription ID | `azure_subscription_id` | in terraform.tfvars | Terraform provider |

### 4.1 secrets.env aanmaken

```bash
cd kubernetes-app/INFRA/terraform

# Kopieer het template:
cp secrets.env.example secrets.env

# Vul je echte waarden in:
nano secrets.env    # of: code secrets.env
```

Inhoud van `secrets.env`:

```bash
export TF_VAR_postgres_password="MijnSuperSterkWachtwoord123!"   # min 16 chars
export TF_VAR_jwt_secret="$(openssl rand -hex 32)"               # auto-generate
export TF_VAR_github_token="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx"    # GitHub PAT

export POSTGRES_PASSWORD="${TF_VAR_postgres_password}"
export JWT_SECRET="${TF_VAR_jwt_secret}"
export GITHUB_TOKEN="${TF_VAR_github_token}"
```

### 4.2 Source het bestand

```bash
source secrets.env
```

> ⚠ **`secrets.env` staat in `.gitignore`** — het wordt nooit gecommit.
> Als je `git status` doet, mag `secrets.env` daar NIET staan.

### 4.3 GitHub PAT aanmaken

1. Ga naar: **GitHub → Settings → Developer settings → Personal access tokens → Fine-grained**
2. Maak een token aan met scope: **`read:packages`** (Contents: Read)
3. Repository: `DemirEvren/sqli-analyse`
4. Kopieer de token (`ghp_...`) naar `secrets.env`

### 4.4 terraform.tfvars aanmaken

```bash
# Kopieer het template (als je dat nog niet hebt):
cp terraform.tfvars.example terraform.tfvars

# Vul je subscription ID in:
nano terraform.tfvars
```

> ℹ `terraform.tfvars` bevat ALLEEN non-sensitive waarden (regio, VM-sizes, etc.).
> Alle wachtwoorden/tokens gaan via `secrets.env` → environment variables.

---

## 5. Stap 1 — Terraform bootstrap

> Dit maakt de remote state backend aan (Storage Account in de tfstate RG).
> Hoeft maar **één keer** — daarna deelt het hele team dezelfde state.

```bash
cd kubernetes-app/INFRA/terraform

# Zorg dat secrets geladen zijn:
source secrets.env

# Draai de bootstrap:
cd bootstrap
terraform init
terraform apply -auto-approve

# Noteer de output:
#   storage_account_name = "tfstateshlfwrXXXX"
#   resource_group_name  = "rg-shelfware-tfstate"

cd ..
```

De `deploy.sh` doet dit automatisch en schrijft `backend.conf`, maar je kunt het ook handmatig doen:

```bash
cat > backend.conf <<EOF
resource_group_name  = "rg-shelfware-tfstate"
storage_account_name = "<de naam uit terraform output>"
container_name       = "tfstate"
key                  = "shelfware/terraform.tfstate"
EOF
```

---

## 6. Stap 2 — Terraform apply

### Optie A: Automatisch via `deploy.sh` (aanbevolen)

```bash
cd kubernetes-app/INFRA/terraform
source secrets.env
bash deploy.sh
```

Het script doet alles: prereq check → Azure login → secrets → bootstrap → init → build images → 2-stage apply → kubeconfig → ArgoCD bootstrap.

### Optie B: Handmatig (stap voor stap)

```bash
cd kubernetes-app/INFRA/terraform
source secrets.env

# 1. Init met remote backend:
terraform init -backend-config=backend.conf -reconfigure

# 2. Plan (optioneel — bekijk wat er gaat gebeuren):
terraform plan

# 3. Stage 1 — Azure infra (~15-20 minuten):
terraform apply -auto-approve \
  -target=module.monitoring \
  -target=module.networking \
  -target=module.aks_app \
  -target=module.aks_loadtest

# 4. Stage 2 — Kubernetes namespaces + secrets (~2 minuten):
terraform apply -auto-approve

# 5. Export kubeconfig:
export KUBECONFIG="$(pwd)/kubeconfigs/merged.yaml"

# Check:
kubectl config get-contexts
kubectl get nodes --context shelfware-app
kubectl get nodes --context shelfware-loadtest
```

---

## 7. Stap 3 — ArgoCD bootstrap

> ArgoCD installeert alle workloads (shelfware frontend/backend, postgres, monitoring, ingress) via GitOps.

```bash
cd kubernetes-app/INFRA/terraform
export KUBECONFIG="$(pwd)/kubeconfigs/merged.yaml"

# Source secrets (nodig voor GITHUB_TOKEN, POSTGRES_PASSWORD, JWT_SECRET):
source secrets.env

# Draai het bootstrap script:
bash bootstrap-aks.sh
```

Dit installeert:
- ArgoCD op beide clusters
- Ingress-nginx (app cluster)
- Monitoring stack: Prometheus + Grafana + Kepler (app cluster)
- Shelfware frontend/backend/postgres (app cluster, prod + test namespace)
- Locust load-test (loadtest cluster)
- OpenCost (app cluster)

---

## 8. Stap 4 — Verificatie

```bash
export KUBECONFIG="kubernetes-app/INFRA/terraform/kubeconfigs/merged.yaml"

# ── AKS clusters ──────────────────────────────────────────────────────────
kubectl get nodes --context shelfware-app
kubectl get nodes --context shelfware-loadtest

# ── ArgoCD applicaties ────────────────────────────────────────────────────
kubectl get applications -n argocd --context shelfware-app
kubectl get applications -n argocd --context shelfware-loadtest

# ── Shelfware pods ────────────────────────────────────────────────────────
kubectl get pods -n prod-shelfware --context shelfware-app
kubectl get pods -n test-shelfware --context shelfware-app

# ── Monitoring ────────────────────────────────────────────────────────────
kubectl get pods -n monitoring --context shelfware-app
kubectl get pods -n opencost --context shelfware-app

# ── Ingress IP ────────────────────────────────────────────────────────────
INGRESS_IP=$(kubectl get svc ingress-nginx-controller \
  -n ingress-nginx --context shelfware-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Shelfware: http://${INGRESS_IP}"
echo "Grafana:   http://${INGRESS_IP}/grafana"
```

---

## 9. Stap 5 — kanalyzer installeren

### 9.1 Python virtual environment

```bash
cd kanalyzer

# Maak venv aan:
python3 -m venv .venv
source .venv/bin/activate    # Windows WSL: idem

# Installeer kanalyzer:
pip install -e .
```

### 9.2 kanalyzer secrets (optioneel)

```bash
cp .env.example .env
nano .env   # vul API keys in als je die hebt (Teams webhook, Datadog, Electricity Maps)
source .env
```

> ℹ kanalyzer werkt ook **zonder** API keys — dan krijg je alleen stdout-output, geen Teams-alerts.

### 9.3 kanalyzer.yaml configureren voor AKS

Voor AKS-clusters hoef je geen port-forwards te doen als je `prometheus_url` en `opencost_url` direct instelt:

```yaml
# kanalyzer.yaml voor AKS
cluster_name: shelfware-app

prometheus:
  url: http://localhost:9090   # of: directe URL als je port-forward draait

opencost:
  url: http://localhost:9003

# Bij AKS: start port-forwards zo:
#   kubectl port-forward svc/monitoring-stack-kube-prom-prometheus 9090:9090 -n monitoring --context shelfware-app &
#   kubectl port-forward svc/opencost 9003:9003 -n opencost --context shelfware-app &
```

---

## 10. Stap 6 — kanalyzer draaien

### Eenmalige analyse

```bash
cd kanalyzer
source .venv/bin/activate
source .env   # als je API keys hebt

# Start port-forwards (als je niet direct URL's gebruikt):
kubectl port-forward svc/monitoring-stack-kube-prom-prometheus 9090:9090 -n monitoring --context shelfware-app &
kubectl port-forward svc/opencost 9003:9003 -n opencost --context shelfware-app &

# Draai de volledige pipeline:
kanalyzer pipeline

# Of alleen een rapport:
kanalyzer report --output-dir reports/

# Multi-cluster analyse:
kanalyzer multi-cluster pipeline
```

### Dagelijkse automatisering (GitLab CI/CD)

Zie sectie 12 voor GitLab CI/CD configuratie.

---

## 11. Secrets: waar staat wat?

```
┌─────────────────────────────────────────────────────────────────┐
│  NOOIT in Git                    │  WEL in Git                  │
├─────────────────────────────────────────────────────────────────┤
│  terraform.tfvars                │  terraform.tfvars.example    │
│  secrets.env                     │  secrets.env.example         │
│  backend.conf                    │  backend.conf.example        │
│  kubeconfigs/                    │  .gitignore                  │
│  kanalyzer/.env                  │  kanalyzer/.env.example      │
│  kanalyzer/kanalyzer.local.yaml  │  kanalyzer/kanalyzer.yaml    │
│  *.tfstate / .terraform/         │  kanalyzer.example.yaml      │
└─────────────────────────────────────────────────────────────────┘
```

### Hoe secrets veilig doorstromen

```
secrets.env  ──source──▶  TF_VAR_postgres_password  ──▶  terraform apply
                          TF_VAR_jwt_secret               │
                          TF_VAR_github_token              ▼
                                                    Kubernetes Secrets
                                                    (encrypted at rest)
                                                          │
                                                          ▼
                                                    Pod environment vars
                                                    (injected by kubelet)
```

| Laag | Encryptie | Wie kan lezen? |
|---|---|---|
| `secrets.env` (lokale file) | Geen (plaintext) | Alleen jouw laptop |
| GitLab CI/CD Variables | Masked + protected | Alleen CI/CD runners |
| Terraform state (Azure Blob) | AES-256 at rest + TLS in transit | Azure RBAC |
| Kubernetes Secrets | AES-256 at rest (Azure disk encryption) | RBAC: alleen pods in namespace |

---

## 12. GitLab CI/CD secrets

Als jullie later naar GitLab gaan, stel je de secrets in als **CI/CD Variables**:

### 12.1 Terraform secrets

Ga naar: **GitLab → Settings → CI/CD → Variables**

| Key | Value | Options |
|---|---|---|
| `TF_VAR_postgres_password` | je wachtwoord | ✅ Masked, ✅ Protected |
| `TF_VAR_jwt_secret` | je JWT secret | ✅ Masked, ✅ Protected |
| `TF_VAR_github_token` | `ghp_...` | ✅ Masked, ✅ Protected |
| `ARM_CLIENT_ID` | SP client ID | ✅ Masked, ✅ Protected |
| `ARM_CLIENT_SECRET` | SP secret | ✅ Masked, ✅ Protected |
| `ARM_TENANT_ID` | tenant ID | ✅ Protected |
| `ARM_SUBSCRIPTION_ID` | subscription ID | ✅ Protected |

### 12.2 kanalyzer secrets

| Key | Value | Options |
|---|---|---|
| `KANALYZER_WEBHOOK_URL` | Teams webhook URL | ✅ Masked, ✅ Protected |
| `KANALYZER_REPORT_URL` | GitLab Pages URL | ✅ Protected |
| `DATADOG_API_KEY` | Datadog API key | ✅ Masked, ✅ Protected |
| `DATADOG_APP_KEY` | Datadog APP key | ✅ Masked, ✅ Protected |
| `ELECTRICITY_MAPS_API_KEY` | Electricity Maps key | ✅ Masked, ✅ Protected |
| `KUBECONFIG_CONTENT` | Base64-encoded kubeconfig | ✅ Masked, ✅ Protected |

### 12.3 Kubeconfig voor CI/CD

```bash
# Genereer base64-encoded kubeconfig:
base64 -w 0 kubernetes-app/INFRA/terraform/kubeconfigs/merged.yaml

# Plak de output als KUBECONFIG_CONTENT in GitLab CI/CD Variables.
```

---

## 13. Troubleshooting

### "The resource group does not exist"

```
Error: Resource Group "rg-shelfware-prod" was not found
```

→ **Oplossing:** vraag je admin om de resource group aan te maken (zie sectie 3.1).

### "AuthorizationFailed" bij terraform apply

```
Error: authorization failed for resource ... role assignment
```

→ **Oplossing:** je mist een van de 6 rollen. Vraag je admin om de ontbrekende rol toe te kennen (zie sectie 3.2). Controleer met:

```bash
az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv)" \
  --scope "/subscriptions/<sub-id>/resourceGroups/rg-shelfware-prod" -o table
```

### "Missing required variable" bij terraform apply

```
Error: No value for required variable "postgres_password"
```

→ **Oplossing:** je hebt `source secrets.env` niet gedaan. Of secrets.env is leeg.

### Kubernetes providers falen bij eerste apply

```
Error: Provider "kubernetes" configuration is invalid
```

→ **Normaal bij eerste keer.** Gebruik de 2-stage apply (zie sectie 6, optie B, stap 3+4). Na stage 1 bestaan de clusters, waarna stage 2 werkt.

### Port-forward faalt voor kanalyzer

```
error: unable to forward port because pod is not running
```

→ **Oplossing:** wacht tot de monitoring-pods draaien:

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus -n monitoring --context shelfware-app --timeout=300s
```

---

## 14. Destroy (opruimen)

### Via deploy.sh

```bash
cd kubernetes-app/INFRA/terraform
source secrets.env
bash deploy.sh --destroy
```

### Handmatig

```bash
cd kubernetes-app/INFRA/terraform
source secrets.env

terraform destroy -auto-approve

# Optioneel: ook de tfstate backend opruimen:
cd bootstrap
terraform destroy -auto-approve
```

> ⚠ Na destroy moet je admin de resource groups ook verwijderen (Terraform kan ze niet deleten omdat het data sources zijn).

```bash
# Admin draait:
az group delete --name rg-shelfware-prod --yes
az group delete --name rg-shelfware-tfstate --yes
```

---

## Snelle referentie — volledige volgorde

```bash
# ── 0. Eenmalig: admin maakt RGs + rollen aan (sectie 3) ─────────────────

# ── 1. Clone ──────────────────────────────────────────────────────────────
git clone https://github.com/DemirEvren/sqli-analyse.git
cd sqli-analyse/kubernetes-app/INFRA/terraform

# ── 2. Secrets ────────────────────────────────────────────────────────────
cp secrets.env.example secrets.env
nano secrets.env                     # vul in: postgres wachtwoord, JWT, GitHub PAT
source secrets.env

# ── 3. tfvars ─────────────────────────────────────────────────────────────
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars                # vul subscription_id in

# ── 4. Bootstrap (eenmalig) ──────────────────────────────────────────────
cd bootstrap && terraform init && terraform apply -auto-approve && cd ..

# ── 5. Init ──────────────────────────────────────────────────────────────
terraform init -backend-config=backend.conf -reconfigure

# ── 6. Deploy Stage 1 (Azure infra, ~15 min) ─────────────────────────────
terraform apply -auto-approve \
  -target=module.monitoring \
  -target=module.networking \
  -target=module.aks_app \
  -target=module.aks_loadtest

# ── 7. Deploy Stage 2 (K8s namespaces + secrets) ─────────────────────────
terraform apply -auto-approve

# ── 8. Kubeconfig ─────────────────────────────────────────────────────────
export KUBECONFIG="$(pwd)/kubeconfigs/merged.yaml"
kubectl get nodes --context shelfware-app

# ── 9. ArgoCD + workloads ─────────────────────────────────────────────────
bash bootstrap-aks.sh

# ── 10. kanalyzer ─────────────────────────────────────────────────────────
cd ../../../kanalyzer
python3 -m venv .venv && source .venv/bin/activate && pip install -e .
cp .env.example .env && nano .env && source .env
kanalyzer pipeline
```

---

*Laatste update: 4 maart 2026*
