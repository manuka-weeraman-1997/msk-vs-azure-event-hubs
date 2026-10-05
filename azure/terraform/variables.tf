# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------

variable "subscription_id" {
  description = "Azure subscription ID. Leave null to use ARM_SUBSCRIPTION_ID or the Azure CLI context. Never commit a real value."
  type        = string
  default     = null
}

variable "project" {
  description = "Short project name used in resource names and tags."
  type        = string
  default     = "market-data"
}

variable "environment" {
  description = "Environment label used in names and tags (for example dev, staging, prod)."
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Resource group
# ---------------------------------------------------------------------------

variable "create_resource_group" {
  description = "Create the resource group. Set false to deploy into an existing one named by resource_group_name."
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Resource group name. Created when create_resource_group is true, otherwise looked up. Null derives a name from project and environment."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Event Hubs namespace (parallel to the MSK cluster on the AWS side)
# ---------------------------------------------------------------------------

variable "namespace_name" {
  description = "Event Hubs namespace name. The default streaming-prod is a placeholder: real namespace names are globally unique across Azure, so choose your own."
  type        = string
  default     = "streaming-prod"
}

variable "sku" {
  description = "Namespace tier: Basic, Standard or Premium. The Kafka-compatible endpoint requires Standard or higher."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be Basic, Standard or Premium."
  }
}

variable "capacity" {
  description = "Throughput units (Basic/Standard) or processing units (Premium). Check current Microsoft documentation for allowed ranges and auto-inflate behaviour."
  type        = number
  default     = 1
}

variable "minimum_tls_version" {
  description = "Minimum TLS version accepted by the namespace."
  type        = string
  default     = "1.2"
}

variable "public_network_access_enabled" {
  description = "Allow access over the public endpoint. Set false together with enable_private_endpoint for private-only access."
  type        = bool
  default     = true
}

variable "local_authentication_enabled" {
  description = "Allow SAS keys. Set false to require Microsoft Entra ID only (recommended once clients are migrated)."
  type        = bool
  default     = true
}

variable "topics" {
  description = "Event hubs to create, keyed by name (the Kafka topic equivalent). The $Default consumer group exists automatically and must not be listed."
  type = map(object({
    partition_count        = number
    message_retention_days = number
    consumer_groups        = list(string)
  }))
  default = {
    "market-events" = {
      partition_count        = 4
      message_retention_days = 1
      consumer_groups        = ["search-service", "analytics"]
    }
  }
}

# ---------------------------------------------------------------------------
# Networking (optional Private Endpoint)
# ---------------------------------------------------------------------------

variable "enable_private_endpoint" {
  description = "Create a VNet, subnet, Private Endpoint and private DNS zone for the namespace. Off by default."
  type        = bool
  default     = false
}

variable "vnet_address_space" {
  description = "VNet address space (documentation-style example range)."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "private_endpoint_subnet_prefix" {
  description = "Subnet prefix for the Private Endpoint. Must sit inside vnet_address_space."
  type        = string
  default     = "10.0.1.0/24"
}

# ---------------------------------------------------------------------------
# Access (Microsoft Entra ID role assignments)
# ---------------------------------------------------------------------------

variable "sender_principal_ids" {
  description = "Object IDs granted 'Azure Event Hubs Data Sender' on the namespace (producers)."
  type        = list(string)
  default     = []
}

variable "receiver_principal_ids" {
  description = "Object IDs granted 'Azure Event Hubs Data Receiver' on the namespace (consumers)."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Monitoring (parallel to CloudWatch on the AWS side)
# ---------------------------------------------------------------------------

variable "log_retention_days" {
  description = "Log Analytics workspace retention in days."
  type        = number
  default     = 30
}

variable "alert_email_addresses" {
  description = "Addresses notified by the action group. Empty list creates the group with no receivers."
  type        = list(string)
  default     = []
}

variable "throttled_requests_threshold" {
  description = "Alert when total ThrottledRequests over the window exceeds this value."
  type        = number
  default     = 0
}

variable "server_errors_threshold" {
  description = "Alert when total ServerErrors over the window exceeds this value."
  type        = number
  default     = 0
}
