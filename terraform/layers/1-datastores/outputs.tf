# Outputs for the datastore layer.
#
# No output exposes a password. Connection strings are assembled by the consumer from these
# parts and a credential taken from the environment, so a secret never enters Terraform
# state through an output.

output "application_database" {
  description = "Database the application uses."
  value       = var.application_database
}

output "managed_roles" {
  description = "Roles this layer manages."
  value       = sort(keys(local.role_privileges))
}

output "role_privileges" {
  description = "Privileges each managed role receives, for review before anything is applied."
  value       = local.role_privileges
}

output "read_only_roles" {
  description = <<-EOT
    Roles that must not be able to create objects.

    Verify against the live instance rather than trusting the plan:

      sudo -u postgres psql -d novashop -c \
        "SELECT has_schema_privilege('novashop_exporter', 'public', 'CREATE');"

    Expect f. It returned t before the grant was revoked from PUBLIC.
  EOT
  value       = local.read_only_roles
}

output "redis_endpoint" {
  description = "Host and port pods use to reach Redis. No credential."
  value       = "${var.redis_bind_addresses[0]}:${var.redis_port}"
}

output "redis_config_hash" {
  description = "Content hash of the rendered Redis configuration."
  value       = local.redis_config_hash
}

output "managed_by" {
  description = "Marker identifying resources in this layer as Terraform-managed."
  value       = local.managed_by
}
