# Backend abstraction.
#
# The block is deliberately empty. A partial configuration lets the same code initialise
# against local state during a rebuild and against PostgreSQL in steady state, without the
# backend choice being committed to the layer:
#
#   terraform init -backend-config=../../examples/backend-pg.hcl
#
# -backend-config supplies arguments to the declared type; it cannot change the type. A
# local run uses examples/backend-local-override.tf.example copied in as
# backend_override.tf, which Terraform merges over this block.
#
# CI initialises with -backend=false, so validation needs no credentials at all.
#
# This layer is the one most likely to run before the node exists — GitHub repositories and
# their protection are what a rebuild starts from. Expect it on local state first, migrated
# with `terraform state push` once PostgreSQL is available.
#
# schema_name is supplied by the backend configuration file rather than here, so that one
# schema per layer is a property of how it is initialised and a mistaken destroy in one
# layer cannot reach another.

terraform {
  backend "pg" {}
}
