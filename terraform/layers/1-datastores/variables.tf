# Input interface for the datastore layer.

variable "postgres_host" {
  description = "Address the provider connects to. The node's LAN address, not localhost — pods reach PostgreSQL here too."
  type        = string
}

variable "postgres_port" {
  description = "PostgreSQL port."
  type        = number
  default     = 5432
}

variable "postgres_superuser" {
  description = "Role used to manage roles and grants."
  type        = string
  default     = "postgres"
}

variable "postgres_superuser_password" {
  description = "Password for postgres_superuser. Supply through TF_VAR_postgres_superuser_password."
  type        = string
  sensitive   = true
}

variable "postgres_sslmode" {
  description = "libpq sslmode. Defaults to require so the platform fails closed rather than silently connecting in clear text."
  type        = string
  default     = "require"

  validation {
    condition     = contains(["disable", "require", "verify-ca", "verify-full"], var.postgres_sslmode)
    error_message = "Must be one of: disable, require, verify-ca, verify-full."
  }
}

variable "application_database" {
  description = "Database the application uses."
  type        = string
  default     = "novashop"
}

variable "application_role" {
  description = "Role the application connects as. Owns the schema and may write."
  type        = string
  default     = "novashop"
}

variable "exporter_role" {
  description = <<-EOT
    Role postgres-exporter connects as. Read-only.

    This is the reason the layer exists. PostgreSQL 14 grants CREATE on the public schema
    to PUBLIC — PostgreSQL 15 removed that — so pg_monitor alone left the exporter able to
    create tables in the application's database. The grant is revoked from PUBLIC and given
    to the application role only.

    That correction is currently a SQL snippet someone ran once and a sentence in a
    document. Modelling it here makes it desired state with drift detection: if the grant
    comes back, the plan says so.
  EOT
  type        = string
  default     = "novashop_exporter"
}

variable "redis_bind_addresses" {
  description = "Addresses Redis binds to. Must include the node's LAN address; localhost alone is unreachable from pods."
  type        = list(string)

  validation {
    condition     = length(var.redis_bind_addresses) > 0
    error_message = "At least one bind address is required."
  }
}

variable "redis_port" {
  description = "Redis port."
  type        = number
  default     = 6379
}

variable "revoke_public_schema_create" {
  description = <<-EOT
    Revoke CREATE on the public schema from PUBLIC.

    Defaults to true. Set false only for a PostgreSQL 15 or later instance, where the grant
    does not exist and revoking it is a no-op rather than a correction.
  EOT
  type        = bool
  default     = true
}
