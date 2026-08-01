# Backend abstraction. See ../3-github/backend.tf for the reasoning; it is identical.
#
# One consideration specific to this layer: DNS is on the critical path for certificate
# renewal, not only for reachability. HTTP-01 validation requires the public name to reach
# this node on port 80, so losing or corrupting this state has a consequence that does not
# surface for up to sixty days — the existing certificate keeps working until renewal is
# attempted.
#
# That is why this layer gets its own schema, and why later phases put prevent_destroy on
# every record.

terraform {
  backend "pg" {}
}
