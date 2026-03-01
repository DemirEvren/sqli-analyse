# ─── Module: monitoring ───────────────────────────────────────────────────────
# Creates Azure-side monitoring infrastructure:
#  • Log Analytics Workspace (Container Insights, AKS diagnostics)
#  • Azure Monitor Workspace (Prometheus-compatible managed scraping — optional)
#  • Diagnostic settings for both AKS clusters
#
# In-cluster monitoring (kube-prometheus-stack, Grafana, Kepler) is deployed
# by ArgoCD via INFRA/monitoring/kustomize — this module only handles the
# Azure platform layer.
# ─────────────────────────────────────────────────────────────────────────────

# ─── Log Analytics Workspace ──────────────────────────────────────────────────
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.prefix}-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_days

  tags = var.tags
}

# NOTE: AKS diagnostic settings live in root main.tf (not here) to avoid a
# module-level circular dependency:
#   monitoring → (needs) aks cluster IDs → aks → (needs) monitoring workspace ID
# Keeping the Log Analytics workspace here breaks the cycle cleanly.

# ─── Azure Monitor Workspace (managed Prometheus — optional) ─────────────────
# This is Azure's hosted Prometheus service. In our setup we run in-cluster
# Prometheus (more flexibility, Kepler integration), but the managed workspace
# is created here as an opt-in for production use.
resource "azurerm_monitor_workspace" "main" {
  count = var.managed_prometheus_enabled ? 1 : 0

  name                = "${var.prefix}-ampw"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}
