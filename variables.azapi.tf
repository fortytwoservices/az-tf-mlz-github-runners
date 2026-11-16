variable "ignore_body_changes" {
  type = object({
    compute_virtual_machine_scale_sets = optional(list(string), [])
    network_network_security_groups    = optional(list(string), [])
    authorization_role_assignments     = optional(list(string), [])

    managedidentity_user_assigned_identities = optional(object({
      managedidentity_user_assigned_identities = optional(list(string), [])
    }), {})
  })
  default     = {}
  description = <<DESCRIPTION
Paths in each resource's `body` whose changes the AzAPI provider ignores. Prefer Terraform's `lifecycle.ignore_changes` when the paths are static; use this variable when the paths must be derived from variables or other non-static values.

Paths use dot notation, for example `properties.virtualMachineProfile.storageProfile`. Individual list items cannot be targeted; ignore the whole list property instead. Configuration changes at an ignored path are **not** sent to Azure until that path is removed from the list. Changes take effect only after an apply, because the value is held in provider-private state.

- `compute_virtual_machine_scale_sets` - Ignored body paths for the scale set.
- `network_network_security_groups` - Ignored body paths for the network security group.
- `authorization_role_assignments` - Ignored body paths for the identity's role assignment on the App key's secret.
- `managedidentity_user_assigned_identities` - Slot for the runners' identity (`az-tf-mlz-user-assigned-identity`).
  - `managedidentity_user_assigned_identities` - The user-assigned identity.
DESCRIPTION
  nullable    = false
}

variable "resource_types" {
  type = object({
    compute_virtual_machine_scale_sets = optional(string, "Microsoft.Compute/virtualMachineScaleSets@2026-03-01")
    network_network_security_groups    = optional(string, "Microsoft.Network/networkSecurityGroups@2025-07-01")
    authorization_role_assignments     = optional(string, "Microsoft.Authorization/roleAssignments@2022-04-01")

    managedidentity_user_assigned_identities = optional(object({
      managedidentity_user_assigned_identities = optional(string)
    }), {})
  })
  default     = {}
  description = <<DESCRIPTION
Override the AzAPI `<provider>/<resource>@<api-version>` strings used by this module. Each key defaults to a tested value; supply only the keys you want to override.

- `compute_virtual_machine_scale_sets` - The virtual machine scale set.
- `network_network_security_groups` - The network security group on the runners' network interfaces.
- `authorization_role_assignments` - The identity's role assignment on the App key's secret.
- `managedidentity_user_assigned_identities` - Slot for the runners' identity (`az-tf-mlz-user-assigned-identity`). Defaults live in that module.
  - `managedidentity_user_assigned_identities` - The user-assigned identity.
DESCRIPTION
  nullable    = false
}

variable "retry" {
  type = object({
    error_message_regex  = optional(list(string))
    interval_seconds     = optional(number)
    max_interval_seconds = optional(number)
  })
  default     = null
  description = <<DESCRIPTION
Retry configuration applied to every `azapi` resource managed by the module (and the identity module it calls). Defaults to `null` (no custom retry).

- `error_message_regex`  - (Optional) A list of regex patterns matching error messages that trigger a retry.
- `interval_seconds`     - (Optional) Initial interval between retries in seconds.
- `max_interval_seconds` - (Optional) Maximum interval between retries in seconds.

See <https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource#retry> for full semantics.
DESCRIPTION
}

variable "timeouts" {
  type = object({
    create = optional(string)
    read   = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  default     = null
  description = <<DESCRIPTION
Default per-operation timeouts applied to every `azapi` resource managed by the module. Defaults to `null` (provider defaults). Each value is a Go duration string (e.g. `30m`, `1h`).

- `create` - (Optional) Timeout for create operations.
- `read`   - (Optional) Timeout for read operations.
- `update` - (Optional) Timeout for update operations.
- `delete` - (Optional) Timeout for delete operations.
DESCRIPTION
}
