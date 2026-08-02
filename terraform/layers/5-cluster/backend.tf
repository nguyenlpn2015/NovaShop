# Backend abstraction. See ../3-github/backend.tf for the reasoning.
#
# This layer runs after 1-datastores, so PostgreSQL exists and the pg backend is available
# without the ordering caveat that applies to 0-node.
#
# Suggested schema_name: terraform_cluster

terraform {
  backend "pg" {}
}
