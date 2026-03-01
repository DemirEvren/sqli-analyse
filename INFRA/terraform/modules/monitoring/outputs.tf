output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.main.name
}

output "managed_prometheus_id" {
  value = var.managed_prometheus_enabled ? azurerm_monitor_workspace.main[0].id : ""
}
