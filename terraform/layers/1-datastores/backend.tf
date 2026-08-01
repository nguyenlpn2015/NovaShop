# Backend abstraction. See ../3-github/backend.tf for the reasoning.
#
# This layer manages the PostgreSQL instance that the pg backend stores state in. That is
# not the same circularity as 0-node: the database and the server already exist by this
# point, and this layer manages roles and grants inside it.
#
# It is still worth stating, because a destroy here could remove the role the backend
# authenticates as. Later phases put prevent_destroy on the roles for that reason, and the
# backend uses a dedicated role that this layer does not manage.

terraform {
  backend "pg" {}
}
