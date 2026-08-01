# Outputs for the node layer.

output "node_ip" {
  description = "LAN address of the node. Consumed by the datastore layer."
  value       = var.node_ip
}

output "pod_cidr" {
  description = "Pod network CIDR. Consumed by the datastore layer for pg_hba and Redis bind configuration."
  value       = var.pod_cidr
}

output "sysctl_settings" {
  description = "Kernel settings this layer enforces."
  value       = local.sysctl_settings
}

output "sysctl_hash" {
  description = "Content hash of the rendered sysctl drop-in. Changing an input changes this, which is what gives the layer a meaningful plan."
  value       = local.sysctl_hash
}

output "firewall_enabled" {
  description = "Whether UFW is managed. False while management_cidr is null, by design."
  value       = local.firewall_enabled
}

output "firewall_rules" {
  description = "Rules that will be applied, for review before anything is enabled."
  value       = local.firewall_rules
}

output "managed_by" {
  description = "Marker identifying resources in this layer as Terraform-managed."
  value       = local.managed_by
}
