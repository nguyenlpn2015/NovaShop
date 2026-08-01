# Resources this layer owns.
#
# Two things, and the shortness of this file is the point. Almost everything inside the
# cluster is reconciled by Argo CD, so Terraform's contribution here is assertion rather
# than ownership — see data.tf and locals.tf, which are longer for that reason.
#
# What is absent, deliberately:
#
#   No Helm release. Those belong to Argo CD.
#   No Application or AppProject. Those belong to the GitOps repository.
#   No Secret. Creating, importing, or reading one places its value in Terraform state in
#     plaintext, which is weaker than /root/.novashop-platform.env at 0600.
#   No workload of any kind.

# The Argo CD namespace is the only namespace on this cluster that Argo CD does not
# reconcile: the bootstrap script created it before Argo CD existed, which is why its
# managed-by label reads kubectl and why no tracking-id annotation is present.
#
# Every other namespace is either a tracked resource inside an Application or is covered by
# managedNamespaceMetadata on the ApplicationSet, which reapplies its labels on every sync.
# Declaring one of those here would mean two controllers writing one object.
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = var.argocd_namespace

    # These mirror argocd/namespace.yaml, which the bootstrap script applies with kubectl.
    # They must match the cluster exactly or the import plans a change.
    #
    # Two things learned by running it rather than reasoning about it:
    #
    #   kubernetes.io/metadata.name is set by the API server and is not returned by the
    #   provider on read. Declaring it produces a one-line diff on every plan, forever.
    #
    #   The sync-wave annotation had to be declared. Omitting it does not leave it alone —
    #   Terraform plans to remove it, because an undeclared annotation on a managed
    #   resource is one Terraform believes should not be there.
    labels      = var.argocd_namespace_labels
    annotations = var.argocd_namespace_annotations
  }

  lifecycle {
    # Deleting this namespace removes Argo CD and every Application object with it. The
    # cluster would keep running whatever it last converged to, with nothing reconciling it
    # and no way to deploy.
    prevent_destroy = true
  }
}

# A cluster-wide read-only role for verification and incident triage.
#
# New and owned by nothing else. It exists because the only credential currently available
# is the cluster-admin kubeconfig, so every diagnostic command runs with the ability to
# delete the platform. Reading logs during an incident should not require that.
#
# Deliberately excludes secrets: the whole point is a credential that cannot exfiltrate
# credentials.
resource "kubernetes_cluster_role_v1" "viewer" {
  count = var.manage_read_only_role ? 1 : 0

  metadata {
    name = var.read_only_role_name
    labels = {
      "app.kubernetes.io/name"       = var.read_only_role_name
      "app.kubernetes.io/component"  = "rbac"
      "app.kubernetes.io/part-of"    = "novashop-platform"
      "app.kubernetes.io/managed-by" = local.managed_by
    }
  }

  rule {
    api_groups = [""]
    resources = [
      "namespaces",
      "nodes",
      "pods",
      "pods/log",
      "services",
      "endpoints",
      "configmaps",
      "persistentvolumeclaims",
      "persistentvolumes",
      "events",
    ]
    verbs = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets", "daemonsets", "replicasets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["cert-manager.io"]
    resources  = ["certificates", "certificaterequests", "clusterissuers", "issuers"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["argoproj.io"]
    resources  = ["applications", "applicationsets", "appprojects"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["nodes", "pods"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "viewer" {
  count = var.manage_read_only_role && length(var.read_only_subjects) > 0 ? 1 : 0

  metadata {
    name = var.read_only_role_name
    labels = {
      "app.kubernetes.io/name"       = var.read_only_role_name
      "app.kubernetes.io/component"  = "rbac"
      "app.kubernetes.io/part-of"    = "novashop-platform"
      "app.kubernetes.io/managed-by" = local.managed_by
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.viewer[0].metadata[0].name
  }

  dynamic "subject" {
    for_each = var.read_only_subjects
    content {
      api_group = subject.value.kind == "ServiceAccount" ? "" : "rbac.authorization.k8s.io"
      kind      = subject.value.kind
      name      = subject.value.name
      namespace = subject.value.kind == "ServiceAccount" ? subject.value.namespace : null
    }
  }
}
