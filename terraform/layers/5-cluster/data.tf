# Live cluster state, read only.
#
# This layer asserts far more than it owns. That ratio is the design: almost everything
# inside the cluster belongs to Argo CD, so the useful contribution Terraform makes is to
# codify the assumptions the rest of the platform is built on and fail when they stop
# holding.
#
# There is deliberately no data source on any Secret. The kubernetes provider reads the
# whole object, so a data source — like an import — would place the values in Terraform
# state in plaintext. Secret existence is verified with kubectl instead; see the
# secret_verification_command output and ADR 013.

# The single StorageClass. ADR 002 records that local-path being node-local is why a
# PersistentVolumeClaim cannot outlive the node, and why Prometheus, Loki, and Alertmanager
# volumes are excluded from the backup as explicitly disposable. If this assumption changes,
# those decisions need revisiting.
data "kubernetes_storage_class_v1" "primary" {
  metadata {
    name = var.storage_class_name
  }
}

# Every namespace Argo CD reconciles. Read so their existence and Pod Security posture can
# be asserted without Terraform writing to them.
data "kubernetes_namespace_v1" "tracked" {
  for_each = var.argocd_tracked_namespaces

  metadata {
    name = each.key
  }
}

# Cluster-wide facts used by the prerequisite assertions below.
data "kubernetes_nodes" "all" {}
