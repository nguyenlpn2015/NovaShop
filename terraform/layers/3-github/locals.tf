# Derived values for the GitHub layer.
#
# Locals exist here to compute things once and to make the layer's assumptions testable
# through outputs before any resource exists. Everything below is a pure function of the
# input variables, so `terraform plan` evaluates it with no provider and no credential.

locals {
  # Applied to both repositories so anything managed here is identifiable as such. The
  # equivalent of app.kubernetes.io/managed-by on the Kubernetes side.
  managed_by = "terraform"

  common_topics = [
    "devops",
    "gitops",
    "kubernetes",
    "platform-engineering",
    "terraform",
  ]

  # Per-repository topics, deduplicated and sorted so a reordering in a variable does not
  # show up as a diff.
  repository_topics = {
    for name, repo in var.repositories :
    name => sort(distinct(concat(local.common_topics, repo.topics)))
  }

  # One flattened entry per (repository, check) pair. Later phases iterate this with
  # for_each rather than nesting loops inside a resource.
  required_checks_flat = flatten([
    for repo, checks in var.required_status_checks : [
      for check in checks : {
        key        = "${repo}:${check}"
        repository = repo
        check      = check
      }
    ]
  ])

  # Every repository that has checks declared must also be a repository this layer manages.
  # Without this, a typo in a repository name silently produces a ruleset attached to
  # nothing — which looks like protection and is not.
  checks_without_repository = setsubtract(
    keys(var.required_status_checks),
    keys(var.repositories),
  )
}

# Cross-variable invariants cannot live in a variable validation block, so they are checked
# here. A check block reports at plan time and does not block apply, which is the right
# severity: it is a configuration mistake, not a safety failure.
check "every_check_maps_to_a_managed_repository" {
  assert {
    condition = length(local.checks_without_repository) == 0
    error_message = format(
      "required_status_checks names repositories this layer does not manage: %s. A ruleset attached to nothing looks like protection and is not.",
      join(", ", local.checks_without_repository),
    )
  }
}
