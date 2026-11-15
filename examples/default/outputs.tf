output "principal_id" {
  description = "Object ID of the runners' identity."
  value       = module.github_runners.principal_id
}

output "resource_id" {
  description = "Resource ID of the scale set."
  value       = module.github_runners.resource_id
}
