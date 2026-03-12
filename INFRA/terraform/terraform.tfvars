# ─── terraform.tfvars ─────────────────────────────────────────────────────────
# Fill in your values before running `terraform apply`.
# Sensitive values (postgres_password, jwt_secret, github_token) should be
# passed via environment variables instead:
#   export TF_VAR_postgres_password="..."
#   export TF_VAR_jwt_secret="..."
#   export TF_VAR_github_token="..."
# ─────────────────────────────────────────────────────────────────────────────

cloud_provider = "azure"

# Azure
azure_subscription_id    = "430e6120-a54d-43ca-91a8-ea21aa57a800"  # Azure Research and Development
azure_location           = "westeurope"
azure_location_secondary = "northeurope"    # For ACR geo-replication

# Project
project     = "sqli"
environment = "main"

tags = {
  team    = "platform"
  project = "sqli"
}

# AKS — App Cluster
# Mirrors the k3d setup: 1 server + 2 agents with 8 vCPU / 22.8 GiB each
app_cluster_name                = "shelfware-app"
app_cluster_kubernetes_version  = "1.33"
app_cluster_system_node_count   = 1
app_cluster_system_node_vm_size = "Standard_D2s_v3"   # 2 vCPU, 8 GiB  — system pool
app_cluster_user_node_min       = 1
app_cluster_user_node_max       = 5
app_cluster_user_node_vm_size   = "Standard_B2ms"     # 2 vCPU, 8 GiB — user pool (burstable, cheaper)

# AKS — Loadtest Cluster
loadtest_cluster_name                = "shelfware-loadtest"
loadtest_cluster_kubernetes_version  = "1.33"
loadtest_cluster_node_count          = 1
loadtest_cluster_node_vm_size        = "Standard_D2s_v3"

# Monitoring
log_analytics_retention_days = 30
prometheus_retention_days    = 30

# ArgoCD
argocd_repo_url        = "https://github.com/DemirEvren/sqli-analyse.git"
argocd_target_revision = "main"

# GitHub (for image pulls)
github_username = "DemirEvren"

# DNS: leave empty to use <ingress-ip>.nip.io auto-DNS
# dns_zone_name = "shelfware.example.com"
