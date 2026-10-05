# Namespace = the streaming platform (conceptually the MSK cluster, not 1:1).
# Kafka clients connect to <namespace>.servicebus.windows.net:9093 when the
# tier supports the Kafka endpoint (Standard or higher).
resource "azurerm_eventhub_namespace" "this" {
  name                = var.namespace_name
  location            = local.rg_location
  resource_group_name = local.rg_name

  sku      = var.sku
  capacity = var.capacity

  minimum_tls_version           = var.minimum_tls_version
  public_network_access_enabled = var.public_network_access_enabled
  local_authentication_enabled  = var.local_authentication_enabled

  tags = local.tags
}

# Event hub = the Kafka topic equivalent; partition_count matches the topic.
resource "azurerm_eventhub" "this" {
  for_each = var.topics

  name                = each.key
  namespace_name      = azurerm_eventhub_namespace.this.name
  resource_group_name = local.rg_name

  partition_count   = each.value.partition_count
  message_retention = each.value.message_retention_days
}

# The "$Default" consumer group is created automatically with every event hub,
# so it is intentionally not declared here.
resource "azurerm_eventhub_consumer_group" "this" {
  for_each = local.consumer_groups

  name                = each.value.name
  namespace_name      = azurerm_eventhub_namespace.this.name
  eventhub_name       = azurerm_eventhub.this[each.value.event_hub].name
  resource_group_name = local.rg_name
}
