# Derived values for the datastore layer.

locals {
  managed_by = "terraform"

  # Privileges each managed role receives. Written as data rather than as resource bodies so
  # the intent is reviewable in one place and testable through an output before any resource
  # exists.
  role_privileges = {
    (var.application_role) = {
      login         = true
      description   = "Application role. Reads and writes the application schema."
      database      = var.application_database
      schema        = "public"
      privileges    = ["SELECT", "INSERT", "UPDATE", "DELETE"]
      schema_create = true
    }
    (var.exporter_role) = {
      login         = true
      description   = "Metrics exporter. Read-only, and specifically must not be able to create objects."
      database      = var.application_database
      schema        = "public"
      privileges    = ["SELECT"]
      schema_create = false
    }
  }

  # Rendered as the Redis configuration will appear on disk. The hash is the trigger, so a
  # change to a bind address produces a specific diff rather than an unconditional rerun.
  redis_config_content = join("\n", concat(
    ["# Managed by Terraform. See terraform/layers/1-datastores."],
    ["bind ${join(" ", var.redis_bind_addresses)}"],
    ["port ${var.redis_port}"],
    ["protected-mode yes"],
  ))

  redis_config_hash = sha256(local.redis_config_content)

  # Every role that must not be able to create objects. Asserted below and, in a later
  # phase, verified against the live instance.
  read_only_roles = sort([
    for name, cfg in local.role_privileges : name if !cfg.schema_create
  ])
}

# The exporter having write access is the specific regression this layer prevents, so it is
# asserted rather than assumed.
check "exporter_is_read_only" {
  assert {
    condition = alltrue([
      for p in local.role_privileges[var.exporter_role].privileges : p == "SELECT"
    ])
    error_message = "The exporter role must hold SELECT only. It was able to CREATE TABLE once already, because PostgreSQL 14 grants CREATE on public to PUBLIC."
  }
}

check "exporter_cannot_create_in_schema" {
  assert {
    condition     = local.role_privileges[var.exporter_role].schema_create == false
    error_message = "schema_create must be false for the exporter role."
  }
}

# Redis reachable only on loopback is a platform outage that presents as every backend pod
# going unready, so the mistake is worth catching at plan time.
check "redis_is_reachable_from_pods" {
  assert {
    condition     = length([for a in var.redis_bind_addresses : a if a != "127.0.0.1" && a != "::1"]) > 0
    error_message = "redis_bind_addresses contains only loopback. Pods reach Redis over the cluster network, so every backend readiness probe would fail."
  }
}
