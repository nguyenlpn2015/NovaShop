# Outputs for the GitHub layer.
#
# During Phase 1 these expose derived configuration rather than resource attributes, which
# is what makes the layer testable before any resource exists: `terraform plan` renders
# them from variables alone, so the intended ruleset can be diffed against what GitHub
# actually enforces today.
#
# No output exposes a credential. github_token is sensitive and is never surfaced.

output "managed_repositories" {
  description = "Repository names this layer is responsible for."
  value       = sort(keys(var.repositories))
}

output "required_check_names" {
  description = <<-EOT
    Status check names required per repository.

    Compare against the names GitHub has actually reported:

      gh api repos/OWNER/REPO/commits/main/check-runs \
        --jq '.check_runs[].name' | sort -u

    A name here that never appears there is a check that will never report, and a ruleset
    waiting on it blocks every merge.
  EOT
  value       = { for repo, checks in var.required_status_checks : repo => sort(checks) }
}

output "repository_topics" {
  description = "Topics that will be applied per repository, deduplicated and sorted."
  value       = local.repository_topics
}

output "protection_summary" {
  description = "Flat view of what the ruleset will enforce, for review in a pull request."
  value = {
    default_branch     = var.default_branch
    require_reviews    = var.require_pull_request_reviews
    enforce_for_admins = var.enforce_admins
    repositories = {
      for name in keys(var.repositories) : name => {
        checks = sort(lookup(var.required_status_checks, name, []))
      }
    }
  }
}

output "managed_by" {
  description = "Marker identifying resources in this layer as Terraform-managed."
  value       = local.managed_by
}
