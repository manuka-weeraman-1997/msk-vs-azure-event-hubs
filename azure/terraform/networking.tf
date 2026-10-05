# OPTIONAL: everything in this file is created only when
# enable_private_endpoint = true. The default deployment uses the public
# endpoint (protected by TLS 1.2 and Microsoft Entra ID / SAS).
#
# Verify in current Microsoft documentation which namespace tiers support
# Private Endpoints before enabling this, and whether your tier needs extra
# settings. Pair it with public_network_access_enabled = false for
# private-only access.
#
# Conceptual AWS parallel: VPC, private subnets and security groups.

resource "azurerm_virtual_network" "this" {
  count = var.enable_private_endpoint ? 1 : 0

  name                = "vnet-${local.name_prefix}"
  location            = local.rg_location
  resource_group_name = local.rg_name
  address_space       = var.vnet_address_space
  tags                = local.tags
}

resource "azurerm_subnet" "private_endpoints" {
  count = var.enable_private_endpoint ? 1 : 0

  name                 = "snet-private-endpoints"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.this[0].name
  address_prefixes     = [var.private_endpoint_subnet_prefix]
}

resource "azurerm_private_dns_zone" "servicebus" {
  count = var.enable_private_endpoint ? 1 : 0

  name                = "privatelink.servicebus.windows.net"
  resource_group_name = local.rg_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "servicebus" {
  count = var.enable_private_endpoint ? 1 : 0

  name                  = "link-${local.name_prefix}"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.servicebus[0].name
  virtual_network_id    = azurerm_virtual_network.this[0].id
  tags                  = local.tags
}

resource "azurerm_private_endpoint" "namespace" {
  count = var.enable_private_endpoint ? 1 : 0

  name                = "pe-${var.namespace_name}"
  location            = local.rg_location
  resource_group_name = local.rg_name
  subnet_id           = azurerm_subnet.private_endpoints[0].id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${var.namespace_name}"
    private_connection_resource_id = azurerm_eventhub_namespace.this.id
    subresource_names              = ["namespace"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.servicebus[0].id]
  }
}
