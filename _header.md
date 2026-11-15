# az-tf-mlz-github-runners

Self-hosted GitHub Actions runners on an Azure virtual machine scale set, in AzAPI: Fortytwo's managed landing
zone (MLZ) module for runners that live in the customer's own network, so pipelines reach private endpoints
(the Terraform state, Key Vaults) without public access.

Each instance runs Fortytwo's GitHub runner image from Azure Marketplace and registers with GitHub when it
boots, as a GitHub App whose private key it reads from Key Vault. Terraform never reads the key.

## What it creates

- A **virtual machine scale set** (Uniform, Manual upgrades, no overprovisioning) of `instances` runners in the
  subnet given, with managed boot diagnostics, encryption at host and a terminate notification, so a runner
  leaves GitHub before Azure deletes its instance. Registration is in the scale set's model (the Custom
  Script extension), so every instance registers on its first boot.
- A **user-assigned identity** ([`az-tf-mlz-user-assigned-identity`](https://github.com/fortytwoservices/az-tf-mlz-user-assigned-identity)),
  with **Key Vault Secrets User on the App key's secret only**: the runners read that one secret and nothing
  else in the vault.
- A **network security group** on the runners' network interfaces that refuses every inbound connection.

The caller owns the subnet, the Key Vault and the secret (`app_key_secret_resource_id`); a person puts the
App's key in it with `az keyvault secret set --file`.

## Registration

`templates/register.sh.tftpl` runs once per instance, as root:
1. It installs `templates/app-token.sh.tftpl` as `/usr/local/sbin/github-app-token`, which reads the App's key
   from Key Vault with the instance's identity (into memory only), signs a JWT and prints a one-hour
   installation token.
2. It downloads Fortytwo's registration script from
   `fortytwoservices/terraform-azurerm-selfhostedrunnervmss`, pinned to a commit, and runs it only if its
   SHA-256 matches. That script installs the current `actions/runner` as a service and the monitor that
   removes the runner from GitHub on Azure's terminate event.
3. Cron refreshes the saved token every 30 minutes, for that monitor.

The App needs **Organization > Self-hosted runners: write** for organization runners (`github.scope` an
organization, with `github.runner_group`), or **Repository > Administration: write** for repository runners
(`github.scope` `<owner>/<repo>`).

**What a job can reach:** the instance's identity can read the App's key, and the current token sits in the
runner user's home. A job on these runners can use both, so the key can do whatever a job on them may do.
Give the App only the runner permission, in its own App, and let only trusted workflows use the runner group.

## Before the first instance

- Accept the image's terms in the subscription, once: `az vm image terms accept --publisher amestofortytwoas1653635920536 --offer self_hosted_runner_github --plan ubuntu-latest-gen2`.
  The module does not: one agreement serves every scale set in the subscription.
- Register `Microsoft.Compute/EncryptionAtHost` on the subscription, or set `encryption_at_host_enabled = false`.
- Put the App's key in the secret. The vault must use Azure RBAC and be reachable from the subnet.

## Changing the runners

A change to the image, the labels, the runner group or the App reaches new instances, and existing ones only
when they are reimaged: `az vmss reimage --name <name> --resource-group <group> --instance-ids <ids>`, while no
job runs on them. Not `az vmss update-instances`: it runs the registration again on an instance that already
has a runner, which Fortytwo's script refuses ("Runner already exists"), so the extension fails and the runner
keeps its old registration. Raising `instances` adds instances on the current model.

**Cost:** each instance is billed for its compute and, on the default image, for Fortytwo's hourly fee, from the
moment it exists. `instances = 0` stops both.

## Tested

Ported from an azurerm module Fortytwo deployed for a customer on 2026-11-13, where it runs; the
two scripts are that module's, unchanged. Unit tests cover the bodies, the role's scope and the rendered
scripts. **Not yet run in Azure:** this AzAPI version is first deployed with the first MLZ customer (decided
2026-11-15), since a test of the Marketplace image bills Fortytwo. Until then, which body changes Azure
refuses in place (`replace_triggers_external_values`) is unverified.
