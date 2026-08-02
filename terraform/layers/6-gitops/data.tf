# Live GitOps state, read only.
#
# This layer validates the handover it performs. Once the root Application exists and points
# where it should, Terraform's job is finished and Argo CD owns the cluster — so the useful
# assertions are all about whether that handover is intact.
#
# None of these reads a Secret. The repository Secrets this layer manages hold no credential
# by construction, and nothing here reads the ones that do.

# The AppProject the bootstrap script applies. Not reconciled by Argo CD — it has no tracking
# annotation — which is why this layer can be responsible for it.
data "kubernetes_resource" "project" {
  api_version = "argoproj.io/v1alpha1"
  kind        = "AppProject"

  metadata {
    name      = var.project_name
    namespace = var.argocd_namespace
  }
}

# The app-of-apps. Everything else in the cluster descends from this one object, which is
# what makes it the handover point and what makes its source worth asserting.
data "kubernetes_resource" "root_application" {
  api_version = "argoproj.io/v1alpha1"
  kind        = "Application"

  metadata {
    name      = var.root_application_name
    namespace = var.argocd_namespace
  }
}

# Argo CD itself. Read so the running version can be compared against the declared one —
# a script that failed silently, or a manual upgrade, shows up here rather than at the next
# recovery.
# kubernetes_resource rather than kubernetes_deployment_v1: the provider offers the latter
# only as a managed resource, not as a data source, and this layer must read the Deployment
# without claiming to own it. Argo CD's own Deployment belongs to the install manifest.
data "kubernetes_resource" "argocd_server" {
  api_version = "apps/v1"
  kind        = "Deployment"

  metadata {
    name      = "argocd-server"
    namespace = var.argocd_namespace
  }
}
