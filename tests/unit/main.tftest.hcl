mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/networkSecurityGroups/nsg-test"
    }
  }
}
mock_provider "random" {}

override_module {
  target = module.user_assigned_identity
  outputs = {
    client_id    = "22222222-2222-2222-2222-222222222222"
    principal_id = "33333333-3333-3333-3333-333333333333"
    resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-runners"
  }
}

variables {
  name                        = "vmss-runners"
  parent_id                   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test"
  location                    = "norwayeast"
  subnet_resource_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-runners"
  sku_name                    = "Standard_D4ads_v5"
  instances                   = 2
  user_assigned_identity_name = "id-runners"
  network_security_group_name = "nsg-runners"
  app_key_secret_resource_id  = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-kv/providers/Microsoft.KeyVault/vaults/kv-runners/secrets/github-runner-app-key"
  github = {
    scope         = "acme"
    app_client_id = "Iv23liExample"
    labels        = ["mlz", "azure"]
    runner_group  = "mlz"
  }
}

run "organization_runners" {
  command = apply

  assert {
    condition     = azapi_resource.this.type == "Microsoft.Compute/virtualMachineScaleSets@2026-03-01"
    error_message = "The scale set should use the default resource type."
  }
  assert {
    condition     = jsonencode(azapi_resource.this.body.sku) == jsonencode({ capacity = 2, name = "Standard_D4ads_v5", tier = "Standard" })
    error_message = "The scale set should have the size and instance count given."
  }
  assert {
    condition = (
      azapi_resource.this.body.properties.orchestrationMode == "Uniform"
      && azapi_resource.this.body.properties.upgradePolicy.mode == "Manual"
      && azapi_resource.this.body.properties.overprovision == false
    )
    error_message = "Instances should never be reimaged under a running job, and never overprovisioned."
  }
  assert {
    condition     = jsonencode(azapi_resource.this.body.properties.virtualMachineProfile.scheduledEventsProfile.terminateNotificationProfile) == jsonencode({ enable = true, notBeforeTimeout = "PT5M" })
    error_message = "The terminate notification lets the runner leave GitHub before Azure deletes the instance."
  }
  assert {
    condition     = jsonencode(azapi_resource.this.body.plan) == jsonencode({ name = "ubuntu-latest-gen2", product = "self_hosted_runner_github", publisher = "amestofortytwoas1653635920536" })
    error_message = "The default image is Fortytwo's, with its billing plan."
  }
  assert {
    condition     = !can(azapi_resource.this.body.zones)
    error_message = "A regional scale set sends no zones."
  }
  assert {
    condition     = azapi_resource.this.body.properties.virtualMachineProfile.securityProfile.encryptionAtHost
    error_message = "Encryption at host should be on by default."
  }
  assert {
    condition     = azapi_resource.this.body.properties.virtualMachineProfile.osProfile.computerNamePrefix == "vmss-runners"
    error_message = "The host name prefix should default to the name."
  }
  assert {
    condition     = !can(azapi_resource.this.body.properties.virtualMachineProfile.osProfile.adminPassword)
    error_message = "The password must never be in the body: it goes through sensitive_body, write-only."
  }
  assert {
    condition     = azapi_resource.this.sensitive_body_version["properties.virtualMachineProfile.osProfile.adminPassword"] == "creation"
    error_message = "The password should be sent only when the scale set is created."
  }
  assert {
    condition     = one(azapi_resource.this.body.properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].properties.ipConfigurations).properties.subnet.id == var.subnet_resource_id
    error_message = "The runners should join the subnet given."
  }
  assert {
    condition     = azapi_resource.this.body.properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].properties.networkSecurityGroup.id == azapi_resource.network_security_group.id
    error_message = "The runners' network interfaces should carry the module's network security group."
  }
  assert {
    condition     = jsonencode(azapi_resource.this.identity[0].identity_ids) == jsonencode(["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-runners"])
    error_message = "The runners should carry their user-assigned identity."
  }
  assert {
    condition = (
      length(azapi_resource.network_security_group.body.properties.securityRules) == 1
      && azapi_resource.network_security_group.body.properties.securityRules[0].properties.access == "Deny"
      && azapi_resource.network_security_group.body.properties.securityRules[0].properties.direction == "Inbound"
      && azapi_resource.network_security_group.body.properties.securityRules[0].properties.sourceAddressPrefix == "*"
    )
    error_message = "The network security group should deny every inbound connection, and nothing else."
  }

  # The identity reads the App key's secret, and only that secret.
  assert {
    condition     = azapi_resource.app_key_reader.parent_id == var.app_key_secret_resource_id
    error_message = "The role should be assigned on the secret, not on the vault."
  }
  assert {
    condition     = azapi_resource.app_key_reader.body.properties.roleDefinitionId == "/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6"
    error_message = "The role should be Key Vault Secrets User, from the secret's subscription."
  }
  assert {
    condition     = azapi_resource.app_key_reader.body.properties.principalId == "33333333-3333-3333-3333-333333333333" && azapi_resource.app_key_reader.body.properties.principalType == "ServicePrincipal"
    error_message = "The role should go to the runners' identity, as a service principal."
  }

  # The registration script: Fortytwo's script, pinned and checked, run for the organization's runner group.
  assert {
    condition     = base64decode(azapi_resource.this.body.properties.virtualMachineProfile.extensionProfile.extensions[0].properties.protectedSettings.script) == local.registration_script
    error_message = "The extension should run the rendered registration script."
  }
  assert {
    condition     = strcontains(local.registration_script, "-s \"acme\" -u \"runneradmin\" -l \"mlz,azure\" -r \"mlz\" -f")
    error_message = "The runners should register with the organization, labels and runner group given."
  }
  assert {
    condition     = strcontains(local.registration_script, "8c5fed251010ac1ef7941180b6b19260453acc3d0c26f132ce51bc41aec39b18") && strcontains(local.registration_script, "/e76faf2f6395963ae01e9136d197cb23a341db2b/scripts/script.sh")
    error_message = "Fortytwo's script should be pinned to a commit and checked against its hash."
  }
  assert {
    condition = alltrue([
      for expected in [
        "client_id=22222222-2222-2222-2222-222222222222",
        "https://kv-runners.vault.azure.net/secrets/github-runner-app-key?api-version=7.4",
        "\"$((now + 540))\" \"Iv23liExample\"",
        "https://api.github.com/orgs/acme/installation",
      ] : strcontains(base64decode(regex("echo '([^']+)' \\| base64 -d", local.registration_script)[0]), expected)
    ])
    error_message = "The token helper should read the secret with the runners' identity, and sign in to the organization's installation as the App."
  }
}

run "repository_runners" {
  command = plan

  variables {
    github = {
      scope         = "acme/payments"
      app_client_id = "Iv23liExample"
      labels        = ["mlz"]
    }
  }

  assert {
    condition     = strcontains(local.registration_script, "-s \"acme/payments\" -u \"runneradmin\" -l \"mlz\" -f") && !strcontains(local.registration_script, " -r ")
    error_message = "Repository runners register with the repository and no runner group."
  }
  assert {
    condition     = strcontains(base64decode(regex("echo '([^']+)' \\| base64 -d", local.registration_script)[0]), "https://api.github.com/repos/acme/payments/installation")
    error_message = "Repository runners take their token from the App's installation on the repository."
  }
}

run "another_image_zones_and_disk" {
  command = plan

  variables {
    image = {
      publisher = "Canonical"
      offer     = "ubuntu-24_04-lts"
      sku       = "server"
    }
    zones                = ["1", "2", "3"]
    computer_name_prefix = "runner"
    os_disk              = { storage_account_type = "Premium_LRS", size_gb = 128 }
  }

  assert {
    condition     = !can(azapi_resource.this.body.plan)
    error_message = "An image without a plan sends none."
  }
  assert {
    condition     = jsonencode(azapi_resource.this.body.zones) == jsonencode(["1", "2", "3"])
    error_message = "Zones should be sent when given."
  }
  assert {
    condition     = jsonencode(azapi_resource.this.body.properties.virtualMachineProfile.storageProfile.imageReference) == jsonencode({ offer = "ubuntu-24_04-lts", publisher = "Canonical", sku = "server", version = "latest" })
    error_message = "The image should be the one given, at its latest version."
  }
  assert {
    condition     = jsonencode(azapi_resource.this.body.properties.virtualMachineProfile.storageProfile.osDisk) == jsonencode({ caching = "ReadWrite", createOption = "FromImage", diskSizeGB = 128, managedDisk = { storageAccountType = "Premium_LRS" } })
    error_message = "The OS disk should have the type and size given."
  }
  assert {
    condition     = azapi_resource.this.body.properties.virtualMachineProfile.osProfile.computerNamePrefix == "runner"
    error_message = "computer_name_prefix should win over the name."
  }
  assert {
    condition     = jsonencode(azapi_resource.this.replace_triggers_external_values) == jsonencode({ admin_username = "runneradmin", computer_name_prefix = "runner", zones = ["1", "2", "3"] })
    error_message = "What Azure fixes at creation should replace the scale set."
  }
}

run "an_organization_runner_needs_a_group" {
  command = plan

  variables {
    github = {
      scope         = "acme"
      app_client_id = "Iv23liExample"
      labels        = ["mlz"]
    }
  }

  expect_failures = [var.github]
}

run "a_repository_runner_has_no_group" {
  command = plan

  variables {
    github = {
      scope         = "acme/payments"
      app_client_id = "Iv23liExample"
      labels        = ["mlz"]
      runner_group  = "mlz"
    }
  }

  expect_failures = [var.github]
}

run "labels_are_written_into_the_script" {
  command = plan

  variables {
    github = {
      scope         = "acme"
      app_client_id = "Iv23liExample"
      labels        = ["mlz\" ; rm -rf /"]
      runner_group  = "mlz"
    }
  }

  expect_failures = [var.github]
}

run "the_secret_is_a_secret" {
  command = plan

  variables {
    app_key_secret_resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-kv/providers/Microsoft.KeyVault/vaults/kv-runners"
  }

  expect_failures = [var.app_key_secret_resource_id]
}

run "a_name_that_is_no_host_name" {
  command = plan

  variables {
    name = "vmss_runners.01"
  }

  expect_failures = [azapi_resource.this]
}
