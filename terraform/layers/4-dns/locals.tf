# Derived values for the DNS layer.

locals {
  # Fully qualified name per record. Records are keyed relative to the zone so the apex can
  # be expressed as "@" without special-casing it at every use.
  fqdns = {
    for name, _ in var.records :
    name => name == "@" ? var.zone_name : "${name}.${var.zone_name}"
  }

  # The names Let's Encrypt must be able to reach on port 80. Everything downstream of a
  # certificate depends on this set being correct and reachable.
  acme_required_fqdns = sort([
    for name, record in var.records : local.fqdns[name] if record.acme_required
  ])

  # Records to create, with the resolved address folded in so the resource body in a later
  # phase stays a straightforward for_each with no logic in it.
  record_set = {
    for name, record in var.records : name => {
      name    = name
      fqdn    = local.fqdns[name]
      value   = var.site_public_ip
      type    = "A"
      ttl     = record.ttl
      proxied = var.proxied
      comment = coalesce(record.comment, "Managed by Terraform")
    }
  }
}

# A zone with no ACME-required name means no certificate can be issued for anything managed
# here. That is almost certainly a mistake in the variables rather than an intent, and it is
# worth saying at plan time rather than discovering at the next renewal.
check "at_least_one_acme_reachable_name" {
  assert {
    condition     = length(local.acme_required_fqdns) > 0
    error_message = "No record is marked acme_required. HTTP-01 validation needs at least one name reaching this origin on port 80, or no certificate can be issued or renewed."
  }
}
