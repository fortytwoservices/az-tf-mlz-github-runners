variable "app_key_secret_resource_id" {
  type        = string
  description = <<DESCRIPTION
Resource ID of the Key Vault secret holding the GitHub App's private key, the whole PEM file, for example
`/subscriptions/<id>/resourceGroups/<group>/providers/Microsoft.KeyVault/vaults/<vault>/secrets/<name>`.
A person puts it there (`az keyvault secret set --file`); Terraform never reads it. Each instance reads it
with the runners' identity whenever it needs a GitHub token, so the module gives that identity Key Vault
Secrets User on this one secret only. The vault must use Azure RBAC, and the runners' subnet must reach it
(a private endpoint, or its firewall).
DESCRIPTION
  nullable    = false

  validation {
    condition     = can(provider::azapi::parse_resource_id("Microsoft.KeyVault/vaults/secrets", var.app_key_secret_resource_id))
    error_message = "`app_key_secret_resource_id` must be a Key Vault secret's resource ID: .../providers/Microsoft.KeyVault/vaults/<vault>/secrets/<name>."
  }
}

variable "github" {
  type = object({
    scope         = string
    app_client_id = string
    labels        = list(string)
    runner_group  = optional(string)
  })
  description = <<DESCRIPTION
Where the runners register with GitHub, and as which GitHub App.

- `scope` - An organization name for organization runners, or `<owner>/<repo>` for repository runners.
- `app_client_id` - Client ID of the GitHub App the runners register through, for example `Iv23li...`. Not
  secret. The App needs Organization > Self-hosted runners: write for organization runners, or Repository >
  Administration: write for repository runners, and must be installed where they register.
- `labels` - Labels the runners register with, besides GitHub's own (`self-hosted`, `linux`, `x64`).
  Workflows choose them with `runs-on`.
- `runner_group` - (Optional) The organization runner group the runners join, which decides the repositories
  and workflows that may use them. Required for organization runners: without one they would join the
  Default group, which every repository may use. Repository runners have none.

Every value is written into the registration script, so each is limited to the characters GitHub allows.
DESCRIPTION
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+(/[A-Za-z0-9._-]+)?$", var.github.scope))
    error_message = "`github.scope` must be an organization name, or <owner>/<repo>."
  }
  validation {
    condition     = can(regex("^[A-Za-z0-9.]+$", var.github.app_client_id))
    error_message = "`github.app_client_id` must be the App's client ID: letters, digits and dots."
  }
  validation {
    condition     = length(var.github.labels) > 0 && alltrue([for label in var.github.labels : can(regex("^[A-Za-z0-9._-]+$", label))])
    error_message = "`github.labels` needs at least one label, each of letters, digits, dots, underscores and hyphens."
  }
  validation {
    condition     = var.github.runner_group == null ? true : can(regex("^[A-Za-z0-9 ._-]+$", var.github.runner_group))
    error_message = "`github.runner_group` may contain only letters, digits, spaces, dots, underscores and hyphens."
  }
  # A runner group exists only for organization runners, and an organization runner without one would join
  # the Default group, which every repository may use.
  validation {
    condition     = strcontains(var.github.scope, "/") == (var.github.runner_group == null)
    error_message = "Set `github.runner_group` for organization runners (`scope` an organization), and leave it out for repository runners (`scope` <owner>/<repo>)."
  }
}

variable "instances" {
  type        = number
  description = "Number of runners. Each is billed for its compute, and on the default image also for Fortytwo's hourly fee, from the moment it exists, whether or not a job runs on it. 0 removes them all and stops both."
  nullable    = false

  validation {
    condition     = var.instances >= 0 && var.instances <= 100 && floor(var.instances) == var.instances
    error_message = "`instances` must be a whole number from 0 to 100."
  }
}

variable "location" {
  type        = string
  description = "Azure region of the runners, for example `norwayeast`. The subnet must be in it."
  nullable    = false
}

variable "name" {
  type        = string
  description = "Name of the virtual machine scale set."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}[a-zA-Z0-9_]$", var.name))
    error_message = "`name` must be 2 to 64 characters: letters, digits, periods, underscores and hyphens, starting with a letter or digit and not ending with a period or hyphen."
  }
}

variable "network_security_group_name" {
  type        = string
  description = "Name of the network security group the module puts on the runners' network interfaces. It denies every inbound connection: a runner only ever dials out."
  nullable    = false
}

variable "parent_id" {
  type        = string
  description = "Resource ID of the resource group the runners, their identity and their network security group are created in."
  nullable    = false

  validation {
    condition     = can(provider::azapi::parse_resource_id("Microsoft.Resources/resourceGroups", var.parent_id))
    error_message = "`parent_id` must be a resource group resource ID."
  }
}

variable "sku_name" {
  type        = string
  description = "Virtual machine size of each runner, for example `Standard_D4ads_v5`. It must support Gen2 images and, with `encryption_at_host_enabled`, encryption at host."
  nullable    = false
}

variable "subnet_resource_id" {
  type        = string
  description = "Resource ID of the subnet the runners join. It needs outbound access to GitHub and to the image's and the registration script's downloads, and DNS that resolves the Key Vault and anything the jobs deploy to."
  nullable    = false

  validation {
    condition     = can(provider::azapi::parse_resource_id("Microsoft.Network/virtualNetworks/subnets", var.subnet_resource_id))
    error_message = "`subnet_resource_id` must be a subnet resource ID."
  }
}

variable "user_assigned_identity_name" {
  type        = string
  description = "Name of the user-assigned identity the runners read the GitHub App's key with. Jobs on the runners can use it too, so grant it nothing else."
  nullable    = false
}

variable "admin_username" {
  type        = string
  default     = "runneradmin"
  description = "Administrator account, also the account the runner service runs as. Nobody signs in with it: its password is generated, sent to Azure once and kept nowhere, there is no public IP, and the network security group refuses every inbound connection. Azure fixes it when the scale set is created, so a change replaces the scale set."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.admin_username)) && !contains(["root", "admin", "administrator", "azureuser"], var.admin_username)
    error_message = "`admin_username` must be a Linux user name (lower-case letters, digits, underscores and hyphens, up to 32), and not one Azure refuses."
  }
}

variable "computer_name_prefix" {
  type        = string
  default     = null
  description = "Prefix of the runners' host names, which GitHub shows as the runners' names with a suffix. Defaults to `name`. Azure fixes it when the scale set is created, so a change replaces the scale set."

  validation {
    condition     = var.computer_name_prefix == null ? true : can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,56}[a-zA-Z0-9]$", var.computer_name_prefix))
    error_message = "`computer_name_prefix` must be 2 to 58 letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "encryption_at_host_enabled" {
  type        = bool
  default     = true
  description = "Encrypt the runners' temporary disks and caches at the host, as Fortytwo's own runners do. Needs the `Microsoft.Compute/EncryptionAtHost` feature registered on the subscription, once, or Azure refuses the scale set."
  nullable    = false
}

variable "image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = optional(string, "latest")
    plan = optional(object({
      name      = string
      product   = string
      publisher = string
    }))
  })
  default = {
    publisher = "amestofortytwoas1653635920536"
    offer     = "self_hosted_runner_github"
    sku       = "ubuntu-latest-gen2"
    plan = {
      name      = "ubuntu-latest-gen2"
      product   = "self_hosted_runner_github"
      publisher = "amestofortytwoas1653635920536"
    }
  }
  description = <<DESCRIPTION
The runners' image. The default is Fortytwo's GitHub runner image on Azure Marketplace, which carries what
jobs commonly need, and what the registration script needs (`curl`, `jq`, a `docker` group). Microsoft
bills its plan to the subscription, per instance and hour, on top of the compute. Its terms must be
accepted in the subscription once, before the first instance (`az vm image terms accept`); the module does
not accept them, since one agreement serves every scale set in the subscription.

- `publisher`, `offer`, `sku`, `version` - The Marketplace image. `version` defaults to `latest`: new
  instances get the newest, existing ones keep theirs until reimaged.
- `plan` - (Optional) The image's purchase plan (`name`, `product`, `publisher`), for an image that has one.
DESCRIPTION
  nullable    = false
}

variable "os_disk" {
  type = object({
    storage_account_type = optional(string, "StandardSSD_LRS")
    caching              = optional(string, "ReadWrite")
    size_gb              = optional(number)
  })
  default     = {}
  description = <<DESCRIPTION
The runners' OS disks, managed and deleted with each instance.

- `storage_account_type` - (Optional) `Standard_LRS`, `StandardSSD_LRS` (default), `Premium_LRS`, `StandardSSD_ZRS` or `Premium_ZRS`.
- `caching` - (Optional) `None`, `ReadOnly` or `ReadWrite` (default).
- `size_gb` - (Optional) Size in GB; the image's when unset.
DESCRIPTION
  nullable    = false

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "StandardSSD_ZRS", "Premium_ZRS"], var.os_disk.storage_account_type)
    error_message = "`os_disk.storage_account_type` must be Standard_LRS, StandardSSD_LRS, Premium_LRS, StandardSSD_ZRS or Premium_ZRS."
  }
  validation {
    condition     = contains(["None", "ReadOnly", "ReadWrite"], var.os_disk.caching)
    error_message = "`os_disk.caching` must be None, ReadOnly or ReadWrite."
  }
}

variable "tags" {
  type        = map(string)
  default     = null
  description = "(Optional) Tags of the scale set, its identity and its network security group."
}

variable "zones" {
  type        = list(string)
  default     = []
  description = "Availability zones the runners spread across, for example `[\"1\", \"2\", \"3\"]`; regional when empty. Azure fixes them when the scale set is created, so a change replaces the scale set."
  nullable    = false

  validation {
    condition     = alltrue([for zone in var.zones : contains(["1", "2", "3"], zone)])
    error_message = "`zones` may contain only \"1\", \"2\" and \"3\"."
  }
}
