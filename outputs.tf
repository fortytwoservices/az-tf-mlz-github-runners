output "name" {
  description = "Name of the scale set, for `az vmss reimage` and `az vmss update-instances`."
  value       = azapi_resource.this.name
}

output "network_security_group_resource_id" {
  description = "Resource ID of the network security group on the runners' network interfaces."
  value       = azapi_resource.network_security_group.id
}

output "principal_id" {
  description = "Object (principal) ID of the runners' user-assigned identity. Jobs on the runners can use it too."
  value       = module.user_assigned_identity.principal_id
}

output "resource_id" {
  description = "Resource ID of the scale set."
  value       = azapi_resource.this.id
}

output "user_assigned_identity_client_id" {
  description = "Client ID of the runners' user-assigned identity."
  value       = module.user_assigned_identity.client_id
}

output "user_assigned_identity_resource_id" {
  description = "Resource ID of the runners' user-assigned identity."
  value       = module.user_assigned_identity.resource_id
}
