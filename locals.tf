locals {
  # The App key's secret, its vault and the vault's data-plane address. The vault URI ends with a slash: the
  # token script appends the secret's path to it.
  secret                 = provider::azapi::parse_resource_id("Microsoft.KeyVault/vaults/secrets", var.app_key_secret_resource_id)
  vault                  = provider::azapi::parse_resource_id("Microsoft.KeyVault/vaults", local.secret.parent_id)
  vault_uri              = "https://${local.vault.name}.vault.azure.net/"
  key_vault_secrets_user = "/subscriptions/${local.secret.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6"

  computer_name_prefix = coalesce(var.computer_name_prefix, var.name)
  repository_runners   = strcontains(var.github.scope, "/")

  # Fortytwo's registration script, pinned to a commit, not to main, and checked against its hash before it
  # runs: it runs as root on every instance, so it must not change underneath running runners, and a
  # download that differs is refused rather than run (sha256 checked 2026-11-15).
  registration_script_uri    = "https://raw.githubusercontent.com/fortytwoservices/terraform-azurerm-selfhostedrunnervmss/e76faf2f6395963ae01e9136d197cb23a341db2b/scripts/script.sh"
  registration_script_sha256 = "8c5fed251010ac1ef7941180b6b19260453acc3d0c26f132ce51bc41aec39b18"

  # Registers each instance with GitHub (templates/register.sh.tftpl). It installs the token helper
  # (templates/app-token.sh.tftpl), which turns the App's key in Key Vault into a one-hour installation token,
  # downloads Fortytwo's script under its own name, and hands it the token. Nothing in it is secret.
  registration_script = templatefile("${path.module}/templates/register.sh.tftpl", {
    app_token_script = base64encode(templatefile("${path.module}/templates/app-token.sh.tftpl", {
      client_id         = module.user_assigned_identity.client_id
      vault_uri         = local.vault_uri
      secret_name       = local.secret.name
      app_client_id     = var.github.app_client_id
      scope             = var.github.scope
      user              = var.admin_username
      installation_path = local.repository_runners ? "repos/${var.github.scope}/installation" : "orgs/${var.github.scope}/installation"
    }))
    script_uri    = local.registration_script_uri
    script_sha256 = local.registration_script_sha256
    scope         = var.github.scope
    runner_group  = var.github.runner_group
    user          = var.admin_username
    labels        = join(",", var.github.labels)
  })
}
