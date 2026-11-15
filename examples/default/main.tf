# Subscription from ARM_SUBSCRIPTION_ID or the Azure CLI; credentials from the Azure CLI or OIDC.
provider "azapi" {}

locals {
  location = "swedencentral"
  tags     = { example = "default" }
}

data "azapi_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azapi_resource" "resource_group" {
  type      = "Microsoft.Resources/resourceGroups@2024-11-01"
  name      = "rg-mlz-runners-example-${random_string.suffix.result}"
  parent_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  location  = local.location

  response_export_values = []
  tags                   = local.tags
}

# The runners' subnet. In MLZ it is management's `snet-runners`, whose outbound traffic goes through the hub's
# firewall, which allows GitHub. This disposable example has no firewall, so the subnet keeps Azure's default
# outbound access, set explicitly: newer API versions make subnets private by default, and a runner that cannot
# reach GitHub and the vault never registers.
resource "azapi_resource" "virtual_network" {
  type      = "Microsoft.Network/virtualNetworks@2025-07-01"
  name      = "vnet-mlz-runners-example-${random_string.suffix.result}"
  parent_id = azapi_resource.resource_group.id
  location  = local.location
  body = {
    properties = {
      addressSpace = { addressPrefixes = ["10.90.0.0/24"] }
      subnets = [
        {
          name = "snet-runners"
          properties = {
            addressPrefix         = "10.90.0.0/26"
            defaultOutboundAccess = true
          }
        }
      ]
    }
  }

  response_export_values = []
  tags                   = local.tags
}

# The vault for the GitHub App's private key. A person puts the key in with
# `az keyvault secret set --vault-name <vault> --name github-runner-app-key --file <app>.private-key.pem`;
# the generated value here only makes the secret exist, so the role can be assigned on it.
module "key_vault" {
  source = "git::https://github.com/fortytwoservices/az-tf-mlz-key-vault.git?ref=v0.1.0"

  name      = "kv-mlz-run-${random_string.suffix.result}"
  parent_id = azapi_resource.resource_group.id
  location  = local.location

  # A disposable example. Production keeps purge protection on (the default), and reaches the vault through a
  # private endpoint in the runners' network.
  purge_protection_enabled   = false
  purge_on_destroy           = true
  soft_delete_retention_days = 7
  network_acls = {
    bypass         = "AzureServices"
    default_action = "Allow"
  }

  role_assignments = {
    terraform = {
      role_definition_id_or_name = "Key Vault Secrets Officer"
      principal_id               = data.azapi_client_config.current.object_id
    }
  }

  secrets = {
    app_key = {
      name               = "github-runner-app-key"
      content_type       = "application/x-pem-file"
      generated_password = {}
    }
  }
  tags = local.tags
}

module "github_runners" {
  source = "../../"

  name                        = "vmss-mlz-runners-${random_string.suffix.result}"
  parent_id                   = azapi_resource.resource_group.id
  location                    = local.location
  subnet_resource_id          = "${azapi_resource.virtual_network.id}/subnets/snet-runners"
  sku_name                    = "Standard_D2ads_v5"
  user_assigned_identity_name = "id-mlz-runners-${random_string.suffix.result}"
  network_security_group_name = "nsg-mlz-runners-${random_string.suffix.result}"
  app_key_secret_resource_id  = module.key_vault.secrets["app_key"].resource_id

  # No instances, so nothing boots and nothing is billed until the App's key is in the vault. Raise it then.
  instances = 0
  github = {
    scope         = "example-org"
    app_client_id = "Iv23liExampleClientId"
    labels        = ["mlz"]
    runner_group  = "mlz"
  }
  tags = local.tags
}
