# Provider configuration.
#
# Two access paths, because this layer does two different kinds of work:
#
#   The kubernetes provider registers repositories and reads live state to validate the
#   handover.
#
#   An SSH connection runs the existing installer and bootstrap scripts on the node. They
#   are idempotent, they verify their own work, and they already handle the ordering that
#   Argo CD's CRDs require. Reimplementing that in HCL would be a rewrite of working code
#   for no gain, and a worse one — Terraform cannot wait for a CRD to become Established.

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}
