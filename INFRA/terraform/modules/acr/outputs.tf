output "acr_id" {
  value = azurerm_container_registry.main.id
}

output "login_server" {
  description = "ACR login server hostname (use in image references: <login_server>/shelfware-backend:tag)."
  value       = azurerm_container_registry.main.login_server
}

output "acr_name" {
  value = azurerm_container_registry.main.name
}
