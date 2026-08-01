# Version pins for the DNS layer.
#
# The Cloudflare provider had a breaking major release at v5; pinning on the minor with ~>
# accepts patches and refuses a major. For a layer that holds the records the public site
# and every certificate renewal depend on, an unattended major provider upgrade is not a
# risk worth carrying for convenience.

terraform {
  required_version = "~> 1.9"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.40"
    }
  }
}
