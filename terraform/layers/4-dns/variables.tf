# Input interface for the DNS layer.

variable "cloudflare_api_token" {
  description = "Cloudflare API token scoped to Zone:DNS:Edit on the managed zone. Supply through TF_VAR_cloudflare_api_token."
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Zone identifier for the managed domain."
  type        = string

  validation {
    condition     = can(regex("^[a-f0-9]{32}$", var.cloudflare_zone_id))
    error_message = "A Cloudflare zone ID is 32 lowercase hexadecimal characters."
  }
}

variable "zone_name" {
  description = "Apex domain of the managed zone, for example smartdev.vn."
  type        = string
}

# Validated because an address that is not an address fails at apply time otherwise, after
# Terraform has already decided to change a record the site depends on.
variable "site_public_ip" {
  description = "Public IPv4 address every managed record points at. The FortiGate DNATs 80 and 443 from here to the node."
  type        = string

  validation {
    condition     = can(cidrhost("${var.site_public_ip}/32", 0))
    error_message = "Must be a valid IPv4 address."
  }
}

variable "records" {
  description = <<-EOT
    Records this layer manages, keyed by the name relative to the zone.

    All four point at the same address; separation happens at Traefik by Host header, not
    in DNS.

    acme_required marks the names that must answer HTTP-01 on port 80. It is not decoration
    — the acme_reachable_fqdns output turns an implicit dependency chain into something a
    verification script can assert.
  EOT

  type = map(object({
    comment       = optional(string, "")
    ttl           = optional(number, 1) # 1 means automatic
    acme_required = optional(bool, true)
  }))

  validation {
    condition     = length(var.records) > 0
    error_message = "At least one record must be declared; an empty map would plan the removal of every managed record."
  }

  validation {
    condition     = alltrue([for r in var.records : r.ttl == 1 || (r.ttl >= 60 && r.ttl <= 86400)])
    error_message = "ttl must be 1 (automatic) or between 60 and 86400 seconds."
  }
}

# Deliberately not settable per record.
#
# Enabling the Cloudflare proxy terminates TLS at Cloudflare and can stop the
# /.well-known/acme-challenge/ path reaching this origin unmodified, which breaks HTTP-01
# validation silently — the existing certificate keeps working and the failure appears at
# renewal, up to sixty days later.
#
# Turning the proxy on is a legitimate future change. It requires moving to DNS-01 first.
# Making it a single, deliberate edit here rather than a per-record flag is the point: this
# should never be switched on by someone copying a record definition.
variable "proxied" {
  description = "Whether records are proxied by Cloudflare. Must remain false while ACME validation is HTTP-01."
  type        = bool
  default     = false

  validation {
    condition     = var.proxied == false
    error_message = "Proxying breaks HTTP-01 validation. Move the ClusterIssuer to DNS-01 before changing this, and expect renewal to fail silently if you do not."
  }
}
