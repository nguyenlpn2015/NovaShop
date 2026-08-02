# Backend abstraction. See ../3-github/backend.tf for the reasoning.
#
# Suggested schema_name: terraform_gitops
#
# This is the last layer Terraform runs. After it, the cluster reconciles itself from Git and
# Terraform has no further part until something outside the cluster changes.

terraform {
  backend "pg" {}
}
