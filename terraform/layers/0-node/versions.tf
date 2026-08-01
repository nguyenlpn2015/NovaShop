# Version pins for the node layer.
#
# There is no required_providers block, and that is deliberate rather than an omission.
# This layer uses terraform_data, which is built into Terraform since 1.4, together with
# remote-exec. Adding hashicorp/null to do the same thing would pin a provider for no
# capability.
#
# The consequence is that `terraform init -backend=false` in this layer downloads nothing,
# so CI validates it faster than any other layer.

terraform {
  required_version = "~> 1.9"
}
