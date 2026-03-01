# ─── Module: networking ───────────────────────────────────────────────────────
# Creates:
#  • Virtual Network with three subnets:
#      - subnet_app        (AKS app-cluster node pool)
#      - subnet_loadtest   (AKS loadtest-cluster node pool)
#      - subnet_pe         (private endpoints for ACR, Key Vault, etc.)
#  • NSG attached to each subnet
#  • NAT Gateway for predictable outbound IP (important for IP allowlisting in
#    external services / ghcr.io pull)
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-vnet"
  address_space       = var.address_space
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# ─── Subnets ──────────────────────────────────────────────────────────────────

resource "azurerm_subnet" "app" {
  name                 = "${var.prefix}-subnet-app"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_app_cidr]

  # Required for AKS CNI
  service_endpoints = ["Microsoft.ContainerRegistry"]
}

resource "azurerm_subnet" "loadtest" {
  name                 = "${var.prefix}-subnet-loadtest"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_loadtest_cidr]

  service_endpoints = ["Microsoft.ContainerRegistry"]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "${var.prefix}-subnet-pe"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_pe_cidr]

  # Azure requires network policies to be Disabled on a subnet that hosts
  # private endpoints (otherwise the endpoint IP cannot be resolved).
  # azurerm 3.84+: use the string attribute instead of the deprecated bool.
  private_endpoint_network_policies = "Disabled"
}

# ─── NSGs ─────────────────────────────────────────────────────────────────────

resource "azurerm_network_security_group" "app" {
  name                = "${var.prefix}-nsg-app"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Allow inbound HTTP/HTTPS from internet → ingress-nginx LoadBalancer
  security_rule {
    name                       = "allow-http-ingress"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # Allow AKS management plane (Azure-internal, required)
  security_rule {
    name                       = "allow-aks-tunnel"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9000"
    source_address_prefix      = "AzureCloud"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "loadtest" {
  name                = "${var.prefix}-nsg-loadtest"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  # Loadtest cluster has no public ingress — only outbound to app cluster
}

# ─── NSG associations ─────────────────────────────────────────────────────────

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_subnet_network_security_group_association" "loadtest" {
  subnet_id                 = azurerm_subnet.loadtest.id
  network_security_group_id = azurerm_network_security_group.loadtest.id
}

# ─── NAT Gateway ──────────────────────────────────────────────────────────────
# Gives AKS nodes a stable outbound public IP for:
#   • ghcr.io image pulls
#   • Electricity Maps API calls (kanalyzer)
#   • External services that need IP allowlisting

resource "azurerm_public_ip" "nat" {
  name                = "${var.prefix}-nat-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

resource "azurerm_nat_gateway" "main" {
  name                    = "${var.prefix}-nat"
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  zones                   = ["1"]
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "app" {
  subnet_id      = azurerm_subnet.app.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

resource "azurerm_subnet_nat_gateway_association" "loadtest" {
  subnet_id      = azurerm_subnet.loadtest.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}
