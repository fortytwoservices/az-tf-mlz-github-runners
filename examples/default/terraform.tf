terraform {
  required_version = ">= 1.16, < 2.0"

  required_providers {
    # az-tf-mlz-key-vault needs 2.13.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}
