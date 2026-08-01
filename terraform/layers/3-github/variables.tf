# Input interface for the GitHub layer.

variable "github_owner" {
  description = "GitHub user or organisation that owns both repositories."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", var.github_owner))
    error_message = "Must be a valid GitHub login: alphanumerics and hyphens, 1-39 characters."
  }
}

# No default, and sensitive. A default for a credential is a credential in the repository.
variable "github_token" {
  description = "GitHub token with administration:write on the managed repositories. Supply through TF_VAR_github_token."
  type        = string
  sensitive   = true
}

variable "repositories" {
  description = <<-EOT
    Repositories this layer manages, keyed by repository name.

    Both are existing repositories. Nothing here creates one — later phases import them,
    and the acceptance gate is an empty plan.
  EOT

  type = map(object({
    description  = string
    visibility   = string
    has_issues   = optional(bool, true)
    has_projects = optional(bool, false)
    has_wiki     = optional(bool, false)
    topics       = optional(list(string), [])
  }))

  validation {
    condition     = alltrue([for r in var.repositories : contains(["public", "private"], r.visibility)])
    error_message = "visibility must be \"public\" or \"private\"."
  }
}

variable "default_branch" {
  description = "Protected default branch, identical across both repositories."
  type        = string
  default     = "main"
}

variable "required_status_checks" {
  description = <<-EOT
    Status check names that must pass before a merge, per repository.

    These are the names GitHub reports, which are the job names as rendered in the
    workflow — not the workflow file names. Getting this wrong produces a ruleset that
    blocks every merge while waiting for a check that will never report. The existing
    scripts/apply-branch-protection.sh discovers them from completed runs for that reason,
    and the output of this layer is intended to be compared against that discovery.
  EOT

  type = map(list(string))

  validation {
    condition     = alltrue([for checks in var.required_status_checks : length(checks) > 0])
    error_message = "Every repository must require at least one status check; an empty list is a ruleset that protects nothing."
  }
}

variable "require_pull_request_reviews" {
  description = "Require at least one approving review before merge."
  type        = bool
  default     = true
}

variable "enforce_admins" {
  description = <<-EOT
    Apply the ruleset to administrators as well.

    Defaults to false because this platform has one operator, and a rule an operator cannot
    bypass during an incident on a single-node cluster is a rule that turns an outage into a
    longer outage. This is a deliberate trade, not an oversight.
  EOT
  type        = bool
  default     = false
}
