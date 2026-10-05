terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

# REQUIRES ACCOUNT CONFIGURATION: the target subscription.
# Do not commit a subscription ID. Either export ARM_SUBSCRIPTION_ID before
# running Terraform, or run `az login` and `az account set --subscription <id>`
# and pass subscription_id through an uncommitted tfvars file.
provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
}
