# Derived values for the node layer.
#
# The rendered configuration is the desired state, and its hash is what makes the plan
# meaningful. Wrapping a shell script in remote-exec without a content trigger produces a
# layer whose plan is always empty or always dirty; hashing the rendered template means a
# change to pod_cidr or node_ip shows up as a specific, reviewable diff.
#
# Phase 2 adds the templates and the terraform_data resources that consume these hashes.
# They are computed here now so the interface is settled and reviewable first.

locals {
  managed_by = "terraform"

  sysctl_settings = {
    "fs.inotify.max_user_instances" = var.inotify_max_user_instances
    "fs.inotify.max_user_watches"   = var.inotify_max_user_watches
  }

  # Rendered as the sysctl.d drop-in will appear on disk, so the hash tracks the file
  # content rather than the variable values that happen to produce it.
  sysctl_content = join("\n", concat(
    ["# Managed by Terraform. See terraform/layers/0-node."],
    [for k, v in local.sysctl_settings : "${k} = ${v}"],
  ))

  sysctl_hash = sha256(local.sysctl_content)

  # UFW is configured only when a management network is stated explicitly.
  firewall_enabled = var.management_cidr != null

  firewall_rules = local.firewall_enabled ? [
    { port = 22, proto = "tcp", source = var.management_cidr },
    { port = 80, proto = "tcp", source = "any" },
    { port = 443, proto = "tcp", source = "any" },
  ] : []

  firewall_hash = sha256(jsonencode(local.firewall_rules))

  connection = {
    host = var.node_host
    user = var.node_user
  }
}

# UFW without a management network is the one configuration on this platform that can make
# the node unrecoverable. The refusal is already in configure-datastores.sh; this states it
# at plan time as well, where it is visible in a pull request.
check "firewall_requires_an_explicit_management_network" {
  assert {
    condition     = var.management_cidr == null || can(cidrhost(var.management_cidr, 0))
    error_message = "management_cidr must be a real CIDR covering the operator's actual source address. There is one node and no second machine to recover from."
  }
}
