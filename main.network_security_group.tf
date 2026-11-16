# A runner only ever dials out: to GitHub, to Azure, to what its jobs deploy to. Nothing needs to reach it,
# and without this anything in the virtual network could, the administrator account's SSH included. The
# deny at 4096 outranks Azure's default AllowVnetInBound (65000) and AllowAzureLoadBalancerInBound (65001).
# Outbound keeps Azure's defaults: the subnet's own network security group and the firewall decide it.
resource "azapi_resource" "network_security_group" {
  type      = var.resource_types.network_network_security_groups
  name      = var.network_security_group_name
  parent_id = var.parent_id
  location  = var.location
  body = {
    properties = {
      securityRules = [
        {
          name = "DenyAllInbound"
          properties = {
            description              = "Runners only dial out."
            priority                 = 4096
            direction                = "Inbound"
            access                   = "Deny"
            protocol                 = "*"
            sourcePortRange          = "*"
            destinationPortRange     = "*"
            sourceAddressPrefix      = "*"
            destinationAddressPrefix = "*"
          }
        }
      ]
    }
  }
  ignore_body_changes    = length(var.ignore_body_changes.network_network_security_groups) > 0 ? var.ignore_body_changes.network_network_security_groups : null
  response_export_values = []
  retry                  = var.retry
  tags                   = var.tags

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }
}
