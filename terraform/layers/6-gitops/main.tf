# The handover: Terraform prepares the cluster, then Argo CD reconciles everything.
#
# After the root Application exists and points at the GitOps repository, Terraform has no
# further part in what runs inside the cluster. Every Application, every Helm release, every
# workload descends from that one object and is reconciled from Git.
#
# What is absent, deliberately:
#
#   No kubernetes_manifest for the AppProject or the root Application. That resource type
#     does not support import, and both objects already exist. Declaring them would plan a
#     create, the create would fail on a conflict, and the only way through would be to
#     delete them first — which for an Application carrying a resources-finalizer means
#     cascading deletion of everything it manages.
#
#   No helm_release. Argo CD owns those.
#
#   No Secret containing a credential. The repository Secrets below hold a url and a type
#     because both repositories are public; a check refuses anything else.

# ---------------------------------------------------------------------------
# Argo CD installation
# ---------------------------------------------------------------------------

# The installer is a script, and it stays a script. It applies a large multi-document
# manifest, waits for three CRDs to become Established, waits for every Deployment to become
# Available, and waits on a StatefulSet rollout. Terraform cannot express "wait for a CRD to
# be Established" and would have to poll from a provisioner anyway.
#
# What Terraform contributes is the part the script was weakest at: the version and its
# digest become declarative inputs with validation, and the hash of the pair is the trigger,
# so changing the version without updating the digest is a visible difference rather than a
# silently mismatched pin.
resource "terraform_data" "argocd_install" {
  count = var.run_bootstrap ? 1 : 0

  triggers_replace = {
    intent = local.argocd_install_hash
  }

  connection {
    type        = "ssh"
    host        = var.node_host
    user        = var.node_user
    private_key = var.ssh_private_key
  }

  provisioner "remote-exec" {
    inline = [
      "set -Eeuo pipefail",
      "cd ${var.repository_root}",
      "sudo -E env ARGOCD_VERSION=${var.argocd_version} ARGOCD_NAMESPACE=${var.argocd_namespace} WAIT_TIMEOUT=${var.wait_timeout} bash scripts/linux/install-argocd.sh",
    ]
  }
}

# ---------------------------------------------------------------------------
# The handover itself
# ---------------------------------------------------------------------------

# Applies the AppProject and the root Application, then Argo CD takes over.
#
# Ordering is a real dependency, not a stylistic one: the AppProject must exist before the
# root Application, because Argo CD refuses an Application whose project is missing. The
# script already applies them in one server-side apply for that reason.
resource "terraform_data" "gitops_handover" {
  count = var.run_bootstrap ? 1 : 0

  triggers_replace = {
    intent = local.bootstrap_hash
  }

  depends_on = [terraform_data.argocd_install]

  connection {
    type        = "ssh"
    host        = var.node_host
    user        = var.node_user
    private_key = var.ssh_private_key
  }

  provisioner "remote-exec" {
    inline = [
      "set -Eeuo pipefail",
      "cd ${var.repository_root}",
      "sudo -E env ARGOCD_APPLICATION_MANIFEST=${var.repository_root}/${var.root_application_manifest} ARGOCD_NAMESPACE=${var.argocd_namespace} bash scripts/bootstrap.sh",
    ]
  }
}

# ---------------------------------------------------------------------------
# Repository registration
# ---------------------------------------------------------------------------

# Registers both repositories with Argo CD.
#
# Safe to manage here for one specific reason: both repositories are public, so the Secret
# holds a url and a type and no credential. A repository Secret for a private repository
# would carry a token or an SSH key, and Terraform state stores those in plaintext. The
# check below refuses any key that would make that true.
#
# No project field. Scoping a repository to a project restricts every other project from
# using it, which would break the novashop-platform Applications rendering from the same
# repositories. Unscoped matches the behaviour today: anonymous clone, available to all.
resource "kubernetes_secret_v1" "repository" {
  for_each = var.manage_repository_registration ? var.repositories : {}

  metadata {
    name      = "repo-${each.key}"
    namespace = var.argocd_namespace

    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
      "app.kubernetes.io/part-of"      = "novashop-platform"
      "app.kubernetes.io/managed-by"   = local.managed_by
    }
  }

  data = {
    type = each.value.type
    url  = each.value.url
    name = each.key
  }

  type = "Opaque"
}

# A managed repository Secret must never carry credential material, because Terraform state
# would then hold it in plaintext. Asserted rather than trusted: the guard is what makes the
# exception to "Terraform does not manage Secrets" defensible.
check "repository_secrets_carry_no_credentials" {
  assert {
    condition = length([
      for k, s in kubernetes_secret_v1.repository :
      k if length(setintersection(toset(keys(s.data)), toset(local.credential_keys))) > 0
    ]) == 0
    error_message = "A managed repository Secret declares a credential key. Terraform state stores Secret values in plaintext; a private repository must be registered out of band, the same way the Grafana and exporter credentials are. See ADR 010."
  }
}
