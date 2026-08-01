# Outputs for the k3s layer.

output "k3s_version" {
  description = "Installed k3s version."
  value       = var.k3s_version
}

output "server_args" {
  description = "Arguments the k3s server runs with."
  value       = local.server_args
}

output "install_hash" {
  description = "Content hash of the rendered install command. Changing a version or an argument changes this, which is what gives the layer a meaningful plan."
  value       = local.install_hash
}

output "control_plane_metrics_enabled" {
  description = <<-EOT
    Whether the scheduler and controller-manager bind addresses allow scraping.

    Asserted rather than inferred. When true, expect these to answer:

      kubectl get --raw /metrics
      curl -sk https://127.0.0.1:10259/metrics   # scheduler
      curl -sk https://127.0.0.1:10257/metrics   # controller-manager
  EOT
  value       = local.control_plane_metrics_enabled
}

output "disabled_components" {
  description = "Bundled components disabled. Empty means Traefik and local-path are retained."
  value       = var.disable_components
}

output "managed_by" {
  description = "Marker identifying resources in this layer as Terraform-managed."
  value       = local.managed_by
}
