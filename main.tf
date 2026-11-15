# Self-hosted GitHub runners: a virtual machine scale set on Fortytwo's runner image, each instance registered
# with GitHub at boot. Ported to AzAPI from an azurerm module Fortytwo deployed for a customer on
# 2026-11-13, itself derived from fortytwoservices/terraform-azurerm-selfhostedrunnervmss v2.0.0 (MIT). Linux,
# an existing subnet, no load balancer, no public IP.

# Never used to sign in: no public IP, and the network security group refuses every inbound connection, the
# virtual network's included. Linux needs a password or an SSH key; this one is generated in memory, sent to
# Azure once, when the scale set is created, and kept nowhere, state included. Instances are cattle: to look
# into one, read its boot diagnostics, or reimage it.
ephemeral "random_password" "admin" {
  length           = 24
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!#%*()-_=+[]{}:?"
}

resource "azapi_resource" "this" {
  type      = var.resource_types.compute_virtual_machine_scale_sets
  name      = var.name
  parent_id = var.parent_id
  location  = var.location
  # Uniform orchestration with Manual upgrades: an instance is never reimaged underneath a running job. A
  # change to the model, a new image or script included, reaches new instances, or existing ones on an
  # explicit `az vmss reimage` or `az vmss update-instances`. That is also why registration is in the model,
  # not a separate extension resource: one added afterwards would never reach the instances that exist.
  # `zones` and `plan` are left out when unset: a regional scale set and an image without a plan have none.
  body = merge(
    {
      sku = {
        name     = var.sku_name
        tier     = "Standard"
        capacity = var.instances
      }
      properties = {
        orchestrationMode = "Uniform"
        overprovision     = false
        upgradePolicy     = { mode = "Manual" }
        virtualMachineProfile = {
          osProfile = {
            computerNamePrefix = local.computer_name_prefix
            adminUsername      = var.admin_username
            linuxConfiguration = {
              disablePasswordAuthentication = false
              provisionVMAgent              = true
            }
          }
          storageProfile = {
            imageReference = {
              publisher = var.image.publisher
              offer     = var.image.offer
              sku       = var.image.sku
              version   = var.image.version
            }
            osDisk = merge(
              {
                createOption = "FromImage"
                caching      = var.os_disk.caching
                managedDisk  = { storageAccountType = var.os_disk.storage_account_type }
              },
              var.os_disk.size_gb == null ? {} : { diskSizeGB = var.os_disk.size_gb },
            )
          }
          networkProfile = {
            networkInterfaceConfigurations = [
              {
                name = "nic"
                properties = {
                  primary              = true
                  networkSecurityGroup = { id = azapi_resource.network_security_group.id }
                  ipConfigurations = [
                    {
                      name = "internal"
                      properties = {
                        primary = true
                        subnet  = { id = var.subnet_resource_id }
                      }
                    }
                  ]
                }
              }
            ]
          }
          securityProfile = { encryptionAtHost = var.encryption_at_host_enabled }
          # Managed boot diagnostics: the serial log is the only way to see why an instance never registered.
          diagnosticsProfile = { bootDiagnostics = { enabled = true } }
          # Lets the monitor Fortytwo's script installs (cron, every minute) see the Terminate event and remove
          # the runner from GitHub before Azure deletes the instance. Without it every removed instance stays in
          # GitHub as an offline runner. The monitor uses the token saved at registration, which the token
          # helper keeps current.
          scheduledEventsProfile = {
            terminateNotificationProfile = {
              enable           = true
              notBeforeTimeout = "PT5M"
            }
          }
          extensionProfile = {
            extensions = [
              {
                name = "register-github-runner"
                properties = {
                  publisher               = "Microsoft.Azure.Extensions"
                  type                    = "CustomScript"
                  typeHandlerVersion      = "2.1"
                  autoUpgradeMinorVersion = true
                  # No fileUris: the extension saves an inline script as script.sh, Fortytwo's script has the
                  # same name, and with both the inline one ran itself until the instance could not fork
                  # (found on that deployment, 2026-11-13). The inline script downloads Fortytwo's under its own
                  # name instead.
                  # Protected, so that readers of the scale set do not see it; nothing in it is secret.
                  protectedSettings = { script = base64encode(local.registration_script) }
                }
              }
            ]
          }
        }
      }
    },
    length(var.zones) == 0 ? {} : { zones = var.zones },
    var.image.plan == null ? {} : { plan = var.image.plan },
  )
  # Sent only when the scale set is created; never stored in state. sensitive_body is merge-patched into the
  # body.
  sensitive_body = {
    properties = {
      virtualMachineProfile = {
        osProfile = { adminPassword = ephemeral.random_password.admin.result }
      }
    }
  }
  sensitive_body_version = {
    "properties.virtualMachineProfile.osProfile.adminPassword" = "creation"
  }
  ignore_body_changes = length(var.ignore_body_changes.compute_virtual_machine_scale_sets) > 0 ? var.ignore_body_changes.compute_virtual_machine_scale_sets : null
  # What Azure fixes when a scale set is created, so a change replaces it (unverified in Azure: no Azure
  # test before the first customer deployment). The keys are part of the module's contract: adding one later
  # replaces every deployed scale set.
  replace_triggers_external_values = {
    admin_username       = var.admin_username
    computer_name_prefix = local.computer_name_prefix
    zones                = var.zones
  }
  response_export_values = ["properties.uniqueId"]
  retry                  = var.retry
  tags                   = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [module.user_assigned_identity.resource_id]
  }

  dynamic "timeouts" {
    for_each = var.timeouts == null ? [] : [var.timeouts]
    content {
      create = timeouts.value.create
      read   = timeouts.value.read
      update = timeouts.value.update
      delete = timeouts.value.delete
    }
  }

  lifecycle {
    # computer_name_prefix is validated; name, its default, allows periods and underscores, which host names do not.
    precondition {
      condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,56}[a-zA-Z0-9]$", local.computer_name_prefix))
      error_message = "`name` cannot be the runners' host name prefix (2 to 58 letters, digits and hyphens, starting and ending with a letter or digit): set `computer_name_prefix`."
    }
  }

  # The first instances read the key on their first boot, so the grant must exist before them.
  depends_on = [azapi_resource.app_key_reader]
}
