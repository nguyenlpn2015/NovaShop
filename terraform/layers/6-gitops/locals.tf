# Derived values and handover assertions.

locals {
  managed_by = "terraform"

  # What the installer is asked to produce. Hashed rather than passed piecemeal so a change
  # to either the version or its digest is one visible difference in the plan, and so
  # changing the version without the digest cannot slip through as a no-op.
  argocd_install_intent = jsonencode({
    version   = var.argocd_version
    sha256    = var.argocd_manifest_sha256
    namespace = var.argocd_namespace
  })

  argocd_install_hash = sha256(local.argocd_install_intent)

  # What the handover is asked to produce.
  bootstrap_intent = jsonencode({
    project          = var.project_name
    project_manifest = var.project_manifest
    root_application = var.root_application_name
    root_manifest    = var.root_application_manifest
    repo_url         = var.gitops_repo_url
    target_revision  = var.gitops_target_revision
    path             = var.gitops_path
  })

  bootstrap_hash = sha256(local.bootstrap_intent)

  # Observed handover. Read from the live root Application rather than assumed from the
  # manifest on disk, because the question worth answering is what the cluster is following.
  root_spec        = try(data.kubernetes_resource.root_application.object.spec, {})
  root_source      = try(local.root_spec.source, {})
  observed_repo    = try(local.root_source.repoURL, "<absent>")
  observed_rev     = try(local.root_source.targetRevision, "<absent>")
  observed_path    = try(local.root_source.path, "<absent>")
  observed_project = try(local.root_spec.project, "<absent>")

  root_automated = try(local.root_spec.syncPolicy.automated, null)
  root_self_heal = try(local.root_automated.selfHeal, false)
  root_prune     = try(local.root_automated.prune, false)

  # Repositories the AppProject permits. If a repository is registered but not whitelisted,
  # every Application sourcing from it is refused at sync time — the same class of failure as
  # the AppProject resource whitelist, and just as invisible until it happens.
  project_source_repos = try(data.kubernetes_resource.project.object.spec.sourceRepos, [])

  registered_urls = [for r in var.repositories : r.url]

  unwhitelisted_repositories = var.manage_repository_registration ? setsubtract(
    toset(local.registered_urls),
    toset(local.project_source_repos),
  ) : toset([])

  # Running Argo CD image, for comparison against what this layer declares.
  argocd_running_image = try(
    data.kubernetes_resource.argocd_server.object.spec.template.spec.containers[0].image,
    "<unknown>",
  )

  argocd_running_version = try(
    regex(":(v[0-9]+\\.[0-9]+\\.[0-9]+)$", local.argocd_running_image)[0],
    "<unparsed>",
  )

  # Keys that must never appear in a managed repository Secret.
  credential_keys = ["password", "sshPrivateKey", "tlsClientCertKey", "githubAppPrivateKey", "bearerToken"]
}

# ---------------------------------------------------------------------------
# Handover assertions.
#
# check blocks report at plan time and do not block apply. That is the right severity here:
# these describe whether GitOps is correctly in charge, which an operator must see, and none
# of them is a reason for Terraform to refuse to register a repository.
# ---------------------------------------------------------------------------

check "root_application_tracks_the_gitops_repository" {
  assert {
    condition = local.observed_repo == var.gitops_repo_url
    error_message = format(
      "The root Application tracks %s, not %s. Everything in the cluster descends from this one object, so it following the wrong repository means the whole platform is reconciling from somewhere unintended.",
      local.observed_repo, var.gitops_repo_url,
    )
  }
}

check "root_application_tracks_the_expected_revision" {
  assert {
    condition = local.observed_rev == var.gitops_target_revision
    error_message = format(
      "The root Application tracks revision %s, expected %s. This is one of only two references in the platform deliberately not pinned to a commit SHA; if it has been pinned, no GitOps change can take effect.",
      local.observed_rev, var.gitops_target_revision,
    )
  }
}

check "root_application_renders_the_expected_path" {
  assert {
    condition     = local.observed_path == var.gitops_path
    error_message = "The root Application renders ${local.observed_path}, expected ${var.gitops_path}. A different path means a different set of phases, and therefore a different cluster."
  }
}

check "root_application_belongs_to_the_expected_project" {
  assert {
    condition     = local.observed_project == var.project_name
    error_message = "The root Application belongs to project ${local.observed_project}, expected ${var.project_name}."
  }
}

# Without these two the platform stops being GitOps: it would deploy once and then drift
# freely, with nothing correcting a manual change and nothing removing a deleted resource.
check "root_application_reconciles_automatically" {
  assert {
    condition = local.root_self_heal && local.root_prune
    error_message = format(
      "The root Application has selfHeal=%t prune=%t; both must be true. Without selfHeal a live edit persists silently; without prune a resource deleted from Git stays in the cluster forever.",
      local.root_self_heal, local.root_prune,
    )
  }
}

check "registered_repositories_are_whitelisted_by_the_project" {
  assert {
    condition = length(local.unwhitelisted_repositories) == 0
    error_message = format(
      "Registered but not in the AppProject sourceRepos: %s. Argo CD refuses an Application whose source is not whitelisted, and it refuses it at sync time — so the manifest renders, validates, merges, and fails afterwards.",
      join(", ", local.unwhitelisted_repositories),
    )
  }
}

check "running_argocd_matches_the_declared_version" {
  assert {
    condition = local.argocd_running_version == var.argocd_version
    error_message = format(
      "Argo CD is running %s but this layer declares %s. Either the installer did not run, or the cluster was upgraded outside Terraform. The manifest digest in argocd/install-manifest.sha256 belongs to the declared version, so a mismatch means the digest no longer describes what is installed.",
      local.argocd_running_version, var.argocd_version,
    )
  }
}
