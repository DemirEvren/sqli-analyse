# ─── Module: aks ─────────────────────────────────────────────────────────────
# Creates a single AKS cluster. Called twice from main.tf:
#   1. shelfware-app     (app cluster — ingress, monitoring, ArgoCD, shelfware)
#   2. shelfware-loadtest (loadtest cluster — Locust only)
#
# Features:
#  • Azure CNI (flat networking — pods get VNet IPs, same as k3d flannel CNI)
#  • OIDC Issuer + Workload Identity (replaces legacy SP credential rotation)
#  • Cluster Autoscaler on user node pool
#  • System node pool (CriticalAddonsOnly) + User node pool (shelfware workloads)
#  • Azure RBAC for Kubernetes (kubectl backed by AAD groups)
#  • Log Analytics integration for Container Insights
#  • Defender-for-Containers integration stub (disabled by default for cost)
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # cluster_fqdn is exposed via the azurerm_kubernetes_cluster.main.fqdn attribute
  # (output) — no need to construct it manually.
  is_app_cluster = var.cluster_role == "app"
}

# ─── AKS Cluster ──────────────────────────────────────────────────────────────

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  node_resource_group = "${var.resource_group_name}-${var.cluster_name}-nodes"

  # Ensure NAT gateway associations are created before AKS cluster
  # (fixes race condition: "Subnet must have a NAT gateway associated")
  depends_on = [
    var.subnet_nat_gateway_association_ids,
  ]

  # ─── OIDC + Workload Identity ─────────────────────────────────────────────
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # ─── Network ─────────────────────────────────────────────────────────────
  network_profile {
    network_plugin    = "azure"    # Azure CNI: pods get real VNet IPs
    network_policy    = "azure"    # Azure Network Policy (Calico is the alternative)
    load_balancer_sku = "standard"
    outbound_type     = "userAssignedNATGateway" # Use our pre-provisioned NAT Gateway
                                                  # instead of auto-creating one (saves cost)
    service_cidr       = var.service_cidr         # cluster-internal ClusterIP range
    dns_service_ip     = var.dns_service_ip        # must be inside service_cidr
  }

  # ─── System node pool ─────────────────────────────────────────────────────
  # Runs: coreDNS, konnectivity-agent, metrics-server, azure-ip-masq-agent
  # Taint: CriticalAddonsOnly=true:NoSchedule  (no user workloads here)
  default_node_pool {
    name                = "system"
    node_count          = var.system_node_count
    vm_size             = var.system_node_vm_size
    os_disk_size_gb     = 50
    vnet_subnet_id      = var.subnet_id
    max_pods            = 30
    type                = "VirtualMachineScaleSets"
    only_critical_addons_enabled = true

    node_labels = {
      "nodepool-type" = "system"
      "cluster-role"  = var.cluster_role
    }

    upgrade_settings {
      max_surge = "33%"
    }
  }

  # ─── RBAC — Azure AD ─────────────────────────────────────────────────────
  azure_active_directory_role_based_access_control {
    managed                = true
    azure_rbac_enabled     = true
    # admin_group_object_ids = [var.aks_admin_group_id]  # uncomment to restrict admin access
  }
  local_account_disabled = false # Keep local account enabled so Terraform bootstrap works

  # ─── Identity ─────────────────────────────────────────────────────────────
  identity {
    type = "SystemAssigned"
  }

  # ─── Monitoring (Log Analytics) ───────────────────────────────────────────
  dynamic "oms_agent" {
    for_each = var.log_analytics_workspace_id != "" ? [1] : []
    content {
      log_analytics_workspace_id = var.log_analytics_workspace_id
    }
  }

  # ─── Key Vault Secrets Provider (for Kubernetes secrets from Key Vault) ───
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  # ─── Auto-upgrade channel ─────────────────────────────────────────────────
  automatic_channel_upgrade = "patch" # Auto-apply patch releases (1.30.x → 1.30.y)

  # ─── Maintenance window (avoid upgrades during business hours) ────────────
  maintenance_window {
    allowed {
      day   = "Sunday"
      hours = [0, 1, 2, 3] # 00:00–04:00 UTC (each number = a 1-hr start window)
    }
  }

  tags = var.tags

  lifecycle {
    # Kubernetes version is managed outside Terraform after initial creation
    # to prevent accidental downgrades
    ignore_changes = [
      kubernetes_version,
      default_node_pool[0].node_count, # managed by cluster autoscaler
    ]
  }
}

# ─── User Node Pool (both clusters) ──────────────────────────────────────────
# App cluster: runs shelfware, ingress-nginx, prometheus, grafana, ArgoCD, KEDA.
# Loadtest cluster: runs ArgoCD + Locust (system pool has CriticalAddonsOnly
#   taint so workloads cannot schedule there without a user pool).
# k3d comparison: 2 agent nodes with 8 vCPU / 22.8 GiB each
#   → Standard_D4s_v3 (4 vCPU, 16 GiB) × min 2 gives comparable capacity

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  count = local.is_app_cluster ? 1 : 0

  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.user_node_vm_size
  vnet_subnet_id        = var.subnet_id
  os_disk_size_gb       = 128
  max_pods              = 50

  enable_auto_scaling = true
  min_count           = var.user_node_min
  max_count           = var.user_node_max

  # Only user workloads here — no system pods
  node_taints = []
  node_labels = {
    "nodepool-type" = "user"
    "cluster-role"  = var.cluster_role
    "workload"      = var.cluster_role == "app" ? "shelfware" : "loadtest"
  }

  upgrade_settings {
    max_surge = "1"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [node_count]
  }
}

# ─── RBAC ───────────────────────────────────────────────────────────────────────
# No azurerm_role_assignment resources needed:
#  • ACR removed — images pulled from ghcr.io via ghcr-credentials K8s secret
#  • Cluster admin — local_account_disabled=false, so the kubeconfig written by
#    Terraform already contains a client certificate with full admin access
#
# This means only the built-in "Contributor" role is required to deploy.
# No privileged roles (Owner, User Access Administrator) needed.

# ─── Kubeconfig file ──────────────────────────────────────────────────────────
resource "local_file" "kubeconfig" {
  content              = azurerm_kubernetes_cluster.main.kube_config_raw
  filename             = "${path.root}/kubeconfigs/${var.cluster_name}.yaml"
  file_permission      = "0600"
  directory_permission = "0700"
}
