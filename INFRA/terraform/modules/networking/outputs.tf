output "vnet_id" {
  value = azurerm_virtual_network.main.id
}

output "vnet_name" {
  value = azurerm_virtual_network.main.name
}

output "subnet_app_id" {
  value = azurerm_subnet.app.id
}

output "subnet_loadtest_id" {
  value = azurerm_subnet.loadtest.id
}

output "subnet_pe_id" {
  value = azurerm_subnet.private_endpoints.id
}

output "nat_public_ip" {
  description = "Stable outbound IP of the NAT gateway — whitelist this in external services."
  value       = azurerm_public_ip.nat.ip_address
}

output "nat_gateway_association_app_id" {
  description = "NAT gateway association resource ID for app subnet (for AKS dependency)."
  value       = azurerm_subnet_nat_gateway_association.app.id
}

output "nat_gateway_association_loadtest_id" {
  description = "NAT gateway association resource ID for loadtest subnet (for AKS dependency)."
  value       = azurerm_subnet_nat_gateway_association.loadtest.id
}
