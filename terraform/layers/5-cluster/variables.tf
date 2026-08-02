# Input interface for the cluster layer.

variable "kubeconfig_path" {
  description = "Path to a kubeconfig with cluster-admin. On the node this is /etc/rancher/k3s/k3s.yaml, mode 0600."
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "Context to use. Empty selects the current context."
  type        = string
  default     = ""
}

variable "storage_class_name" {
  description = "The cluster's only StorageClass. k3s ships local-path and nothing replaces it."
  type        = string
  default     = "local-path"
}

variable "expected_node_count" {
  description = <<-EOT
    Nodes this platform expects.

    One. Stated as a variable rather than assumed so the assertion is explicit and so the
    day a second node appears, the assertion fails loudly instead of the platform quietly
    behaving differently than every document claims.
  EOT
  type        = number
  default     = 1

  validation {
    condition     = var.expected_node_count >= 1
    error_message = "A cluster has at least one node."
  }
}

variable "minimum_kubernetes_minor" {
  description = "Lowest Kubernetes minor version the platform's manifests are known to render against."
  type        = number
  default     = 30
}

variable "argocd_namespace" {
  description = "Namespace Argo CD runs in. The only namespace this layer owns."
  type        = string
  default     = "argocd"
}

variable "argocd_namespace_labels" {
  description = <<-EOT
    Labels on the Argo CD namespace.

    These mirror argocd/namespace.yaml, which the bootstrap script applies with kubectl
    before Argo CD exists — which is precisely why Argo CD does not track this namespace and
    Terraform can. The two declarations must stay identical, or whichever ran last wins.

    kubernetes.io/metadata.name is deliberately absent. The API server sets it on every
    namespace, and the provider does not return it on read, so declaring it produces a
    permanent one-line diff that never converges.
  EOT
  type        = map(string)
  default = {
    "app.kubernetes.io/managed-by" = "kubectl"
    "app.kubernetes.io/name"       = "argocd"
    "app.kubernetes.io/part-of"    = "novashop-platform"
  }
}

variable "argocd_namespace_annotations" {
  description = <<-EOT
    Annotations on the Argo CD namespace.

    The sync-wave annotation is present because argocd/namespace.yaml carries it. Omitting
    it here does not leave it alone — Terraform would plan to remove it, because an
    undeclared annotation on a managed resource is an annotation Terraform believes should
    not exist.
  EOT
  type        = map(string)
  default = {
    "argocd.argoproj.io/sync-wave" = "-2"
  }
}

variable "argocd_tracked_namespaces" {
  description = <<-EOT
    Namespaces Argo CD reconciles. Asserted to exist, never managed.

    cert-manager and observability are tracked resources inside Applications.
    novashop-* are covered by managedNamespaceMetadata on the ApplicationSet, which
    reconciles their labels on every sync.

    Terraform declaring any of these would mean two controllers writing one object. See
    ADR 013.
  EOT
  type = map(object({
    enforce = string
    reason  = string
  }))
  default = {
    "cert-manager" = {
      enforce = "restricted"
      reason  = "Tracked by the novashop-cert-manager Application."
    }
    "observability" = {
      enforce = "privileged"
      reason  = "Tracked by the novashop-prometheus Application. node-exporter needs host network and host mounts, which restricted forbids."
    }
    "novashop-development" = {
      enforce = "restricted"
      reason  = "Labels reconciled by managedNamespaceMetadata on the ApplicationSet."
    }
    "novashop-staging" = {
      enforce = "restricted"
      reason  = "Labels reconciled by managedNamespaceMetadata on the ApplicationSet."
    }
    "novashop-production" = {
      enforce = "restricted"
      reason  = "Labels reconciled by managedNamespaceMetadata on the ApplicationSet."
    }
  }
}

variable "required_secrets" {
  description = <<-EOT
    Secrets that must exist for the platform to become healthy, and the keys each must hold.

    This is a contract, not a resource. Terraform does not create, import, or read these —
    doing any of the three would place their values in Terraform state in plaintext, which
    is weaker than /root/.novashop-platform.env at 0600. See ADR 010 and ADR 013.

    What is codified here is the shape: name, namespace, keys, type, and who consumes it.
    The secret_commands output renders the exact kubectl invocation for each, so a rebuild
    is a copy-paste rather than an archaeology exercise.
  EOT
  type = map(object({
    namespace = string
    type      = optional(string, "Opaque")
    keys      = list(string)
    consumer  = string
    purpose   = string
  }))
  default = {
    "novashop-grafana-admin" = {
      namespace = "observability"
      keys      = ["admin-user", "admin-password"]
      consumer  = "Grafana, via admin.existingSecret"
      purpose   = "Grafana administrator credentials."
    }
    "novashop-datastore-exporter" = {
      namespace = "observability"
      keys      = ["postgres-dsn", "redis-password"]
      consumer  = "postgres-exporter and redis-exporter"
      purpose   = "Least-privilege datastore credentials for the metrics exporters."
    }
  }

  validation {
    condition     = alltrue([for s in var.required_secrets : length(s.keys) > 0])
    error_message = "Every declared secret must list at least one key; a contract with no keys asserts nothing."
  }
}

variable "manage_read_only_role" {
  description = <<-EOT
    Create the cluster-wide read-only role used for verification and incident triage.

    New, additive, and owned by nothing else. It exists so diagnosis does not require the
    cluster-admin kubeconfig, which is currently the only credential available.
  EOT
  type        = bool
  default     = true
}

variable "read_only_role_name" {
  description = "Name of the read-only ClusterRole and its binding."
  type        = string
  default     = "novashop-platform-viewer"
}

variable "read_only_subjects" {
  description = <<-EOT
    Subjects bound to the read-only role.

    Empty by default: creating a binding to a subject that does not exist grants nothing and
    hides the fact that nobody is using it. Populate deliberately.
  EOT
  type = list(object({
    kind      = string
    name      = string
    namespace = optional(string, "")
  }))
  default = []

  validation {
    condition     = alltrue([for s in var.read_only_subjects : contains(["User", "Group", "ServiceAccount"], s.kind)])
    error_message = "kind must be User, Group, or ServiceAccount."
  }

  validation {
    condition     = alltrue([for s in var.read_only_subjects : s.kind != "ServiceAccount" || length(s.namespace) > 0])
    error_message = "A ServiceAccount subject requires a namespace."
  }
}
