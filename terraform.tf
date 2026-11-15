terraform {
  # The common floor of the AVM modules MLZ uses: Azure/avm-res-network-privateendpoint 0.3.0 requires
  # 1.16 (Azure/avm-utl-interfaces 0.9.0 needs 1.12: its validations rely on && and || short-circuiting).
  required_version = ">= 1.16, < 2.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    # The administrator password: ephemeral random_password, from 3.7.0, so it is never in state.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
