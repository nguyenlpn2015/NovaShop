# Provider configuration.
#
# Credentials come from TF_VAR_postgres_superuser_password. The provider connects at plan
# time when data sources or resources exist, so during Phase 1 — which declares neither —
# `terraform plan` needs no database.
#
# sslmode is a variable rather than hard-coded: PostgreSQL runs on the same node and is
# reached over the pod or LAN network, so the correct setting depends on whether TLS has
# been configured on the instance. Defaulting it to "require" and letting the platform fail
# closed is safer than defaulting to "disable" for convenience.

provider "postgresql" {
  host      = var.postgres_host
  port      = var.postgres_port
  username  = var.postgres_superuser
  password  = var.postgres_superuser_password
  sslmode   = var.postgres_sslmode
  superuser = false
}
