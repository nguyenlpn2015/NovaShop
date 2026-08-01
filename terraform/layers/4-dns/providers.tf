# Provider configuration.
#
# The API token comes from TF_VAR_cloudflare_api_token. Scope it to Zone:DNS:Edit on the
# single managed zone — a global API key here would be an account-wide credential held for
# four A records.

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
