# Provider configuration.
#
# The token comes from TF_VAR_github_token, never from a .tfvars file. A credential with a
# default, or a credential in a file the repository tracks, is a credential in the
# repository.
#
# No resources exist in this layer yet, so this provider is never initialised at plan time
# during Phase 1. `terraform validate` does not configure providers at all, which is why
# CI can validate every layer without any credential.
#
# Token scope should be the minimum that works: administration:write on the two
# repositories for rulesets and settings, and nothing organisation-wide.

provider "github" {
  owner = var.github_owner
  token = var.github_token
}
