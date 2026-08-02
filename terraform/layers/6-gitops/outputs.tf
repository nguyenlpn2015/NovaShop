# Outputs for the GitOps bootstrap layer.
#
# The point of these is that the handover becomes machine-checkable. Once Terraform has
# finished, "is GitOps correctly in charge" should be a question a script answers, not a
# thing someone remembers to look at.

output "handover" {
  description = "Where the root Application points, as observed on the cluster. This is the boundary between Terraform and Argo CD."
  value = {
    application     = var.root_application_name
    project         = local.observed_project
    repository      = local.observed_repo
    target_revision = local.observed_rev
    path            = local.observed_path
    self_heal       = local.root_self_heal
    prune           = local.root_prune
  }
}

output "argocd" {
  description = "Declared and running Argo CD versions. A mismatch means the installer did not run, or the cluster was upgraded outside Terraform."
  value = {
    declared_version = var.argocd_version
    running_version  = local.argocd_running_version
    running_image    = local.argocd_running_image
    manifest_sha256  = var.argocd_manifest_sha256
    namespace        = var.argocd_namespace
  }
}

output "project_source_repos" {
  description = "Repositories the novashop AppProject permits. An Application sourcing from anything else is refused at sync time."
  value       = local.project_source_repos
}

output "registered_repositories" {
  description = "Repositories registered with Argo CD by this layer. Public only; a private one would put a credential in Terraform state."
  value       = var.manage_repository_registration ? { for k, v in var.repositories : k => v.url } : {}
}

output "terraform_owns" {
  description = "Everything Terraform is responsible for in this layer. Short by design."
  value = concat(
    ["argocd installation (version and digest)", "novashop AppProject", "${var.root_application_name} Application"],
    var.manage_repository_registration ? ["repository registration secrets"] : [],
  )
}

output "argocd_owns_after_handover" {
  description = "What reconciles from Git once this layer has run. Terraform touches none of it."
  value = [
    "novashop-platform AppProject",
    "novashop ApplicationSet and the three environment Applications",
    "cert-manager, certificates, and the TLS phases",
    "prometheus, grafana, loki, alloy, and both exporters",
    "every Helm release and every workload",
  ]
}

output "verification_commands" {
  description = "Commands that prove the handover is intact. Intended for scripts/linux/verify.sh, which does not consume them yet."
  value = {
    root_application = "kubectl -n ${var.argocd_namespace} get application ${var.root_application_name} -o jsonpath='{.status.sync.status}/{.status.health.status}'"
    all_applications = "kubectl -n ${var.argocd_namespace} get applications --no-headers | awk '$2!=\"Synced\" || $3!=\"Healthy\"'"
    argocd_version   = "kubectl -n ${var.argocd_namespace} get deploy argocd-server -o jsonpath='{.spec.template.spec.containers[0].image}'"
    repositories     = "kubectl -n ${var.argocd_namespace} get secret -l argocd.argoproj.io/secret-type=repository"
  }
}

output "managed_by" {
  description = "Marker identifying resources in this layer as Terraform-managed."
  value       = local.managed_by
}
