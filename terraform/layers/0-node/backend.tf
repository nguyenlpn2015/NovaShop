# Backend abstraction. See ../3-github/backend.tf for the reasoning.
#
# This layer configures the node that PostgreSQL runs on, so with the pg backend it is
# genuinely circular on a first build: it cannot store state in a database it has not yet
# prepared the host for.
#
# The resolution is ordering, not cleverness. On a first build or a rebuild this layer runs
# on local state and is migrated with `terraform state push` once PostgreSQL is available.
# In disaster recovery, PostgreSQL is restored before Terraform runs at all — the same
# principle as restoring certificates before Argo CD reconciles.

terraform {
  backend "pg" {}
}
