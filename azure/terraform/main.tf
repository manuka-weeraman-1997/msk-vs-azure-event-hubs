locals {
  name_prefix         = "${var.project}-${var.environment}"
  resource_group_name = coalesce(var.resource_group_name, "rg-${local.name_prefix}")

  tags = merge(
    {
      project     = var.project
      environment = var.environment
      managed_by  = "terraform"
    },
    var.tags
  )

  # Flatten topics -> consumer groups into one map keyed "<hub>/<group>".
  consumer_groups = merge([
    for hub, cfg in var.topics : {
      for group in cfg.consumer_groups : "${hub}/${group}" => {
        event_hub = hub
        name      = group
      }
    }
  ]...)
}

# REQUIRES ACCOUNT CONFIGURATION: with create_resource_group = false the
# resource group must already exist in the target subscription.
resource "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 1 : 0

  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1

  name = local.resource_group_name
}

locals {
  rg_name     = var.create_resource_group ? azurerm_resource_group.this[0].name : data.azurerm_resource_group.existing[0].name
  rg_location = var.create_resource_group ? azurerm_resource_group.this[0].location : data.azurerm_resource_group.existing[0].location
}

# Role assignments are optional: empty principal lists create nothing.
# Built-in roles are referenced by name so no role GUIDs are hardcoded.
# The identity running Terraform needs permission to create role assignments.
resource "azurerm_role_assignment" "sender" {
  for_each = toset(var.sender_principal_ids)

  scope                = azurerm_eventhub_namespace.this.id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "receiver" {
  for_each = toset(var.receiver_principal_ids)

  scope                = azurerm_eventhub_namespace.this.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = each.value
}
