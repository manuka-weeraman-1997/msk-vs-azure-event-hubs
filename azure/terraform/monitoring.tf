# Azure Monitor resources (conceptually CloudWatch on the AWS side).

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.name_prefix}"
  location            = local.rg_location
  resource_group_name = local.rg_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

# Sends all log categories and platform metrics to the workspace.
resource "azurerm_monitor_diagnostic_setting" "namespace" {
  name                       = "diag-${var.namespace_name}"
  target_resource_id         = azurerm_eventhub_namespace.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_action_group" "this" {
  name                = "ag-${local.name_prefix}"
  resource_group_name = local.rg_name
  short_name          = "eh-alerts"
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_addresses

    content {
      name          = "email-${email_receiver.key}"
      email_address = email_receiver.value
    }
  }
}

# Verify metric availability for your tier in the Event Hubs metrics reference.
resource "azurerm_monitor_metric_alert" "throttled_requests" {
  name                = "alert-${var.namespace_name}-throttled-requests"
  resource_group_name = local.rg_name
  scopes              = [azurerm_eventhub_namespace.this.id]
  description         = "Requests are being throttled; consider more throughput units."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.EventHub/namespaces"
    metric_name      = "ThrottledRequests"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.throttled_requests_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_metric_alert" "server_errors" {
  name                = "alert-${var.namespace_name}-server-errors"
  resource_group_name = local.rg_name
  scopes              = [azurerm_eventhub_namespace.this.id]
  description         = "The namespace is returning server errors."
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.EventHub/namespaces"
    metric_name      = "ServerErrors"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.server_errors_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}
