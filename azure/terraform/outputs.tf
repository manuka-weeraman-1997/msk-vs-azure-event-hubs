output "resource_group_name" {
  description = "Resource group holding the deployment."
  value       = local.rg_name
}

output "namespace_name" {
  description = "Event Hubs namespace name."
  value       = azurerm_eventhub_namespace.this.name
}

output "namespace_id" {
  description = "Event Hubs namespace resource ID."
  value       = azurerm_eventhub_namespace.this.id
}

output "kafka_bootstrap_server" {
  description = "Kafka-protocol bootstrap address (Standard tier or higher). Authenticate with Microsoft Entra ID or SAS."
  value       = "${azurerm_eventhub_namespace.this.name}.servicebus.windows.net:9093"
}

output "event_hub_names" {
  description = "Event hubs created (Kafka topic equivalents)."
  value       = keys(azurerm_eventhub.this)
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace receiving namespace logs and metrics."
  value       = azurerm_log_analytics_workspace.this.id
}

output "private_endpoint_id" {
  description = "Private Endpoint ID, or null when enable_private_endpoint is false."
  value       = try(azurerm_private_endpoint.namespace[0].id, null)
}
