# What each instance reads the GitHub App's key with, so Terraform never reads the key: not into state, not
# into a plan, not into the scale set's settings. User-assigned and granted before the scale set exists, so
# the first instances can read the key on their first boot.
module "user_assigned_identity" {
  source = "git::https://github.com/fortytwoservices/az-tf-mlz-user-assigned-identity.git?ref=v0.1.0"

  name                = var.user_assigned_identity_name
  parent_id           = var.parent_id
  location            = var.location
  tags                = var.tags
  resource_types      = var.resource_types.managedidentity_user_assigned_identities
  ignore_body_changes = var.ignore_body_changes.managedidentity_user_assigned_identities
  retry               = var.retry
  timeouts            = var.timeouts
}

# Key Vault Secrets User on the App key's secret alone, not on the vault: the identity reads that one
# secret and nothing else (Key Vault's RBAC guide: a role assigned at a secret's scope). A job on the
# runners can use the identity too, so this is all a job can read with it.
resource "azapi_resource" "app_key_reader" {
  type      = var.resource_types.authorization_role_assignments
  name      = uuidv5("url", "${var.app_key_secret_resource_id}/${var.parent_id}/${var.user_assigned_identity_name}")
  parent_id = var.app_key_secret_resource_id
  body = {
    properties = {
      principalId      = module.user_assigned_identity.principal_id
      principalType    = "ServicePrincipal" # a new identity: Azure would otherwise look it up before it has replicated
      roleDefinitionId = local.key_vault_secrets_user
    }
  }
  # Azure refuses to change a role assignment's principal or role in place (RoleAssignmentUpdateNotPermitted).
  replace_triggers_refs  = ["properties.principalId", "properties.roleDefinitionId"]
  ignore_body_changes    = length(var.ignore_body_changes.authorization_role_assignments) > 0 ? var.ignore_body_changes.authorization_role_assignments : null
  response_export_values = []
  retry                  = var.retry

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
