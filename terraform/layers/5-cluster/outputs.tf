# Outputs for the cluster layer.
#
# These exist to be asserted against rather than read by a person.
#
# Nothing consumes them yet. scripts/linux/verify.sh is the intended consumer and does not
# read them today, so treat these as an interface waiting for a caller, not as wiring that
# already exists. No
# output exposes a secret value, and none can: this layer never reads a Secret.

output "cluster_prerequisites" {
  description = "The assumptions the rest of the platform is built on, as observed."
  value = {
    node_count          = local.node_count
    node_names          = local.node_names
    kubelet_versions    = local.kubelet_versions
    kubernetes_minor    = local.kubernetes_minor
    storage_class       = data.kubernetes_storage_class_v1.primary.metadata[0].name
    storage_provisioner = data.kubernetes_storage_class_v1.primary.storage_provisioner
    reclaim_policy      = data.kubernetes_storage_class_v1.primary.reclaim_policy
    volume_binding      = data.kubernetes_storage_class_v1.primary.volume_binding_mode
  }
}

output "pod_security_posture" {
  description = "Pod Security enforcement observed per Argo CD-tracked namespace."
  value       = local.observed_enforce
}

output "pod_security_drift" {
  description = "Namespaces whose enforcement differs from the declared posture. Empty is healthy."
  value       = local.pod_security_drift
}

output "managed_namespaces" {
  description = "Namespaces this layer owns. Exactly one: everything else is reconciled by Argo CD."
  value       = [kubernetes_namespace_v1.argocd.metadata[0].name]
}

output "asserted_namespaces" {
  description = "Namespaces this layer verifies but does not manage, with the reason ownership sits elsewhere."
  value       = { for k, v in var.argocd_tracked_namespaces : k => v.reason }
}

output "required_secrets" {
  description = <<-EOT
    The secret contract: which Secrets must exist, where, and which keys each must hold.

    Terraform does not create, import, or read these. Any of the three would place their
    values in Terraform state in plaintext, which is weaker than the root-owned 0600 file
    they come from today. See ADR 010 and ADR 013.
  EOT
  value       = var.required_secrets
}

output "secret_commands" {
  description = <<-EOT
    Exact kubectl invocation to create each required Secret, with placeholder values.

    This is what makes the contract reproducible on a rebuild: the key names come from the
    same declaration the charts consume, so they cannot drift apart.
  EOT
  value       = local.secret_commands
}

output "secret_verification_command" {
  description = "One shell command reporting which required Secrets are missing, without printing any value."
  value       = local.secret_verification_command
}

output "read_only_role" {
  description = "The read-only ClusterRole, if managed. Grants get/list/watch and deliberately no access to Secrets."
  value       = var.manage_read_only_role ? var.read_only_role_name : null
}

output "managed_by" {
  description = "Marker identifying resources in this layer as Terraform-managed."
  value       = local.managed_by
}
