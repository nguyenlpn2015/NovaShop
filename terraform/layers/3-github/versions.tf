# Version pins for the GitHub layer.
#
# required_version is pinned on the minor with ~>, so a patch release is accepted and a
# minor is not. Terraform's state format has changed across minors before, and a state
# file written by a newer Terraform cannot be read by an older one — which on a platform
# with one operator means the version on the workstation and the version in CI must not
# drift apart silently.
#
# The provider is pinned the same way, and .terraform.lock.hcl is committed. A provider is
# code that executes with credentials; the reasoning is identical to pinning GitHub Actions
# to commit SHAs rather than tags.

terraform {
  required_version = "~> 1.9"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.6"
    }
  }
}
