# ─── Module: acr ─────────────────────────────────────────────────────────────
# Azure Container Registry for shelfware images.
# Pull access is granted to AKS kubelet identities via role assignment in the
# AKS module (acr_id input variable).
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_container_registry" "main" {
  name                = var.name # globally unique, 5-50 alphanumeric
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = false # Use RBAC + managed identity — never admin credentials

  # Enable on Premium SKU for vulnerability scanning
  quarantine_policy_enabled = var.sku == "Premium" ? true : false

  # Soft-delete: retain deleted images for 7 days
  retention_policy {
    days    = 7
    enabled = true
  }

  trust_policy {
    enabled = false # Enable when using Notary v2 / cosign for image signing
  }

  tags = var.tags
}

# ─── Geo-replication (Premium SKU only) ──────────────────────────────────────
resource "azurerm_container_registry_geo_replication" "secondary" {
  count                 = var.geo_replication_enabled ? 1 : 0
  container_registry_id = azurerm_container_registry.main.id
  location              = var.secondary_location
  zone_redundancy_enabled = false
  tags                  = var.tags
}

# ─── Diagnostic settings → Log Analytics ─────────────────────────────────────
resource "azurerm_monitor_diagnostic_setting" "acr" {
  count = var.log_analytics_workspace_id != "" ? 1 : 0

  name                       = "acr-diag"
  target_resource_id         = azurerm_container_registry.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }
  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }
  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
