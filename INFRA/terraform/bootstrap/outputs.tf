output "resource_group_name" {
  description = "Resource group containing the state backend."
  value       = azurerm_resource_group.tfstate.name
}

output "storage_account_name" {
  description = "Storage account name — use as `storage_account_name` in the main module backend block."
  value       = azurerm_storage_account.tfstate.name
}

output "container_name" {
  description = "Blob container name — use as `container_name` in the main module backend block."
  value       = azurerm_storage_container.tfstate.name
}

output "backend_config" {
  description = "Copy-paste this into the backend block of ../main.tf (or set as TF_BACKEND_* env vars)."
  value = {
    resource_group_name  = azurerm_resource_group.tfstate.name
    storage_account_name = azurerm_storage_account.tfstate.name
    container_name       = azurerm_storage_container.tfstate.name
    key                  = "shelfware/terraform.tfstate"
  }
}
