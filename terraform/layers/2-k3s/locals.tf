# Derived values for the k3s layer.

locals {
  managed_by = "terraform"

  # The full argument list, sorted so reordering a variable is not a diff.
  server_args = sort(concat(
    var.k3s_server_args,
    [for c in var.disable_components : "--disable=${c}"],
  ))

  # The installer invocation, rendered exactly as it will run. Hashing this rather than the
  # individual variables means the trigger tracks what actually changes on the node.
  install_command = join(" ", [
    "INSTALL_K3S_VERSION=${var.k3s_version}",
    "INSTALL_K3S_EXEC=\"server ${join(" ", local.server_args)}\"",
    "sh -s -",
  ])

  install_hash = sha256(local.install_command)

  # Whether the control-plane components will be scrapable with these arguments. Surfaced as
  # an output so the observability gate can assert it instead of inferring it.
  control_plane_metrics_enabled = alltrue([
    contains(var.k3s_server_args, "--kube-scheduler-arg=bind-address=0.0.0.0"),
    contains(var.k3s_server_args, "--kube-controller-manager-arg=bind-address=0.0.0.0"),
  ])
}

# Disabling Traefik here would leave the cluster with no ingress and no way to answer an
# HTTP-01 challenge, which means no certificate could ever be issued. Worth refusing at plan
# time rather than discovering after a restart.
check "traefik_is_not_disabled" {
  assert {
    condition     = !contains(var.disable_components, "traefik")
    error_message = "Disabling Traefik leaves no ingress to answer HTTP-01, so no certificate can be issued. Replace it deliberately or not at all; see ADR 007."
  }
}
