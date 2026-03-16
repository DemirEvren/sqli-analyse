# ─── Root: main.tf ────────────────────────────────────────────────────────────
# Orchestrates all modules for the Shelfware AKS deployment.
#
# Dependency order:
#   1. resource_group (pre-created by Azure admin — looked up as data source)
#   2. monitoring (Log Analytics) — needed by AKS OMS agent
#   3. networking (VNet, subnets, NAT)
#   4. aks_app
#   5. aks_loadtest
#   6. Kubernetes bootstrap resources (namespaces, secrets, ArgoCD)
#
# NOTE: ACR removed — images are pulled from ghcr.io via ghcr-credentials secret.
#       This eliminates all azurerm_role_assignment resources.
#
# RBAC: The deployer needs the following built-in roles on the main RG:
#   • Network Contributor          (4d97b98b-…) — VNet/subnets/NSG/NAT/IP
#   • AKS Contributor Role         (ed7f3fbd-…) — AKS clusters + node pools
#   • Log Analytics Contributor    (92aaf0da-…) — Log Analytics workspace
#   • Monitoring Contributor        (749f88d5-…) — Diagnostic Settings
#
# The resource group itself is NOT created by Terraform. It must be
# pre-created by your Azure admin. Terraform looks it up via a data source.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # Resource group name: must match the pre-created RG in Azure
  rg_name = var.azure_resource_group_name != "" ? var.azure_resource_group_name : "rg-${var.project}-${var.environment}"

  common_tags = merge(
    {
      project     = var.project
      environment = var.environment
      managed-by  = "terraform"
      cloud       = var.cloud_provider
    },
    var.tags,
  )
}

# ─── 1. Resource Group (pre-created by admin) ────────────────────────────────
# The admin creates the RG and assigns the deployer the necessary roles on it.
# Terraform only reads the RG — it does NOT create or destroy it.

data "azurerm_resource_group" "main" {
  name = local.rg_name
}

# ─── 2. Monitoring (Log Analytics) ───────────────────────────────────────────
# Created before AKS so the workspace ID is available for the OMS agent.

module "monitoring" {
  source = "./modules/monitoring"

  prefix              = var.project
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  retention_days      = var.log_analytics_retention_days

  # Diagnostic settings are created as standalone resources below (after AKS)
  # to avoid a circular module dependency.
  managed_prometheus_enabled = false # We use in-cluster Prometheus + Kepler

  tags = local.common_tags
}

# ─── 3. Networking ────────────────────────────────────────────────────────────

module "networking" {
  source = "./modules/networking"

  prefix              = var.project
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  address_space       = var.vnet_address_space

  subnet_app_cidr      = var.subnet_app_cidr
  subnet_loadtest_cidr = var.subnet_loadtest_cidr
  subnet_pe_cidr       = var.subnet_private_endpoints_cidr

  tags = local.common_tags
}

# ─── 4. AKS — App Cluster ──────────────────────────────────────────────────────
# Mirrors the k3d "shelfware-app" cluster:
#   k3d: 1 server + 2 agents, 8 vCPU / 22.8 GiB each, traefik disabled
#   AKS: 1 system node (D2s_v3) + 2–5 user nodes (D4s_v3)

module "aks_app" {
  source = "./modules/aks"

  cluster_name        = var.app_cluster_name
  cluster_role        = "app"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  kubernetes_version  = var.app_cluster_kubernetes_version

  subnet_id = module.networking.subnet_app_id

  system_node_count   = var.app_cluster_system_node_count
  system_node_vm_size = var.app_cluster_system_node_vm_size

  user_node_min     = var.app_cluster_user_node_min
  user_node_max     = var.app_cluster_user_node_max
  user_node_vm_size = var.app_cluster_user_node_vm_size

  # ClusterIP range — must not overlap VNet address space (10.0.0.0/16)
  service_cidr    = "10.100.0.0/16"
  dns_service_ip  = "10.100.0.10"

  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id

  tags = local.common_tags
}

# ─── 5. AKS — Loadtest Cluster (Optional) ──────────────────────────────────
# Mirrors the k3d "shelfware-loadtest" cluster:
#   k3d: 1 server + 2 agents, no loadbalancer, no traefik
#   AKS: system node (CriticalAddonsOnly) + user node pool for ArgoCD + Locust
# Set deploy_loadtest_cluster = true to enable, or false to skip.

module "aks_loadtest" {
  count  = var.deploy_loadtest_cluster ? 1 : 0
  source = "./modules/aks"

  cluster_name        = var.loadtest_cluster_name
  cluster_role        = "loadtest"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  kubernetes_version  = var.loadtest_cluster_kubernetes_version

  subnet_id = module.networking.subnet_loadtest_id

  system_node_count   = var.loadtest_cluster_system_node_count
  system_node_vm_size = var.loadtest_cluster_system_node_vm_size

  # Smaller user pool — quota in West Europe is limited
  # Standard_B4ms = 4 vCPUs × 1 node = 4 vCPUs (vs 8 vCPUs with D4s_v3)
  user_node_vm_size = var.loadtest_cluster_user_node_vm_size
  user_node_min     = var.loadtest_cluster_user_node_count
  user_node_max     = 2

  # Different service CIDR to avoid overlap when both kubeconfigs are merged
  service_cidr    = "10.101.0.0/16"
  dns_service_ip  = "10.101.0.10"

  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id

  tags = local.common_tags
}

# ─── 6. AKS Diagnostic Settings ──────────────────────────────────────────────
# These live in main.tf (not in the monitoring module) to avoid a circular
# module-level dependency. Both modules are fully created before these resources
# are evaluated, so Terraform's resource graph has no cycle.

resource "azurerm_monitor_diagnostic_setting" "aks_app" {
  name                       = "aks-app-diag"
  target_resource_id         = module.aks_app.cluster_id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id

  enabled_log { category = "kube-apiserver" }
  enabled_log { category = "kube-controller-manager" }
  enabled_log { category = "kube-scheduler" }
  enabled_log { category = "kube-audit-admin" }
  enabled_log { category = "guard" }
  enabled_log { category = "cluster-autoscaler" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "aks_loadtest" {
  name                       = "aks-loadtest-diag"
  target_resource_id         = module.aks_loadtest.cluster_id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id

  enabled_log { category = "kube-apiserver" }
  enabled_log { category = "kube-audit-admin" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ─── 7. Kubernetes Bootstrap — App Cluster ────────────────────────────────────
# These resources mirror the manual steps in INFRA/OPERATIONS.md §1.2–1.3:
#   • Namespaces (prod-shelfware, test-shelfware)
#   • Kubernetes Secret: postgres-secret (per namespace)
#   • Kubernetes Secret: ghcr-credentials (imagePullSecret for ghcr.io)
#
# ArgoCD itself is installed by the post-deploy script (bootstrap-aks.sh)
# because Helm chart installation requires a running cluster, and Terraform
# kubernetes/helm providers depend on the cluster being fully ready.

resource "kubernetes_namespace" "prod_shelfware" {
  provider = kubernetes.app
  metadata {
    name = "prod-shelfware"
    labels = {
      environment = "prod"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [module.aks_app]

  timeouts {
    delete = "10m"
  }
}

resource "kubernetes_namespace" "test_shelfware" {
  provider = kubernetes.app
  metadata {
    name = "test-shelfware"
    labels = {
      environment = "test"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [module.aks_app]

  timeouts {
    delete = "10m"
  }
}

# ─── Shelfware secrets (postgres + JWT) ──────────────────────────────────────
# These are the secrets that the kustomize base references as "postgres-secret".

resource "kubernetes_secret" "postgres_prod" {
  provider = kubernetes.app
  metadata {
    name      = "postgres-secret"
    namespace = kubernetes_namespace.prod_shelfware.metadata[0].name
  }

  data = {
    "database-url"      = "postgresql://postgres:${var.postgres_password}@postgres:5432/shelfware?schema=public"
    "postgres-password" = var.postgres_password
    "jwt-secret"        = var.jwt_secret
    "password"          = var.postgres_password # used directly by postgres StatefulSet
  }
}

resource "kubernetes_secret" "postgres_test" {
  provider = kubernetes.app
  metadata {
    name      = "postgres-secret"
    namespace = kubernetes_namespace.test_shelfware.metadata[0].name
  }

  data = {
    "database-url"      = "postgresql://postgres:${var.postgres_password}@postgres:5432/shelfware?schema=public"
    "postgres-password" = var.postgres_password
    "jwt-secret"        = var.jwt_secret
    "password"          = var.postgres_password
  }
}

# ─── GitHub image pull secret ─────────────────────────────────────────────────
# Allows Kubernetes to pull from ghcr.io/demirevren/* without auth errors.

locals {
  dockerconfigjson = jsonencode({
    auths = {
      "ghcr.io" = {
        auth = base64encode("${var.github_username}:${var.github_token}")
      }
    }
  })
}

resource "kubernetes_secret" "ghcr_prod" {
  provider = kubernetes.app
  metadata {
    name      = "ghcr-credentials"
    namespace = kubernetes_namespace.prod_shelfware.metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = local.dockerconfigjson
  }
}

resource "kubernetes_secret" "ghcr_test" {
  provider = kubernetes.app
  metadata {
    name      = "ghcr-credentials"
    namespace = kubernetes_namespace.test_shelfware.metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = local.dockerconfigjson
  }
}

# ─── 7. Kubernetes Bootstrap — Loadtest Cluster ───────────────────────────────

resource "kubernetes_namespace" "locust" {
  provider = kubernetes.loadtest
  metadata {
    name = "locust"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [module.aks_loadtest]

  timeouts {
    delete = "10m"
  }
}

# ─── ArgoCD namespace (created here so the bootstrap script can install into it) ─

resource "kubernetes_namespace" "argocd_app" {
  provider = kubernetes.app
  metadata {
    name = "argocd"
  }

  depends_on = [module.aks_app]

  timeouts {
    delete = "10m"
  }
}

resource "kubernetes_namespace" "argocd_loadtest" {
  provider = kubernetes.loadtest
  metadata {
    name = "argocd"
  }

  depends_on = [module.aks_loadtest]

  timeouts {
    delete = "10m"
  }
}

# ─── ArgoCD repo credential secret ───────────────────────────────────────────
# Mirrors OPERATIONS.md §1.2 "Add repository credentials"

resource "kubernetes_secret" "argocd_repo_app" {
  provider = kubernetes.app
  metadata {
    name      = "argocd-repo-shelfware"
    namespace = kubernetes_namespace.argocd_app.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type = "git"
    url  = var.argocd_repo_url
    # No credentials — repo is public, ArgoCD uses anonymous access
  }
}

resource "kubernetes_secret" "argocd_repo_loadtest" {
  provider = kubernetes.loadtest
  metadata {
    name      = "argocd-repo-shelfware"
    namespace = kubernetes_namespace.argocd_loadtest.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type = "git"
    url  = var.argocd_repo_url
    # No credentials — repo is public, ArgoCD uses anonymous access
  }
}

# ─── Kubeconfig merge (local) ─────────────────────────────────────────────────
# After apply, merge both kubeconfigs into the local ~/.kube/config so
# kubectl / ArgoCD CLI work immediately.

resource "null_resource" "merge_kubeconfig" {
  triggers = {
    app_cluster_id      = module.aks_app.cluster_id
    loadtest_cluster_id = module.aks_loadtest.cluster_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      mkdir -p "${path.root}/kubeconfigs"

      echo "Merging kubeconfigs..."
      KUBECONFIG="${path.root}/kubeconfigs/${var.app_cluster_name}.yaml:${path.root}/kubeconfigs/${var.loadtest_cluster_name}.yaml" \
        kubectl config view --flatten > "${path.root}/kubeconfigs/merged.yaml"

      echo ""
      echo "=== Available contexts ==="
      KUBECONFIG="${path.root}/kubeconfigs/merged.yaml" kubectl config get-contexts
      echo ""
      echo "To use: export KUBECONFIG=${path.root}/kubeconfigs/merged.yaml"
    EOT

    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    module.aks_app,
    module.aks_loadtest,
  ]
}
