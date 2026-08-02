# Input interface for the GitOps bootstrap layer.

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

variable "node_host" {
  description = "Address Terraform reaches the node on over SSH to run the installer scripts."
  type        = string
}

variable "node_user" {
  description = "SSH user with sudo on the node."
  type        = string
}

variable "ssh_private_key" {
  description = "SSH private key for node_user. Supply through TF_VAR_ssh_private_key."
  type        = string
  sensitive   = true
}

variable "repository_root" {
  description = "Path to the NovaShop checkout on the node. The scripts resolve their manifests relative to it."
  type        = string
  default     = "/opt/novashop/NovaShop"
}

# ---------------------------------------------------------------------------
# Argo CD
# ---------------------------------------------------------------------------

variable "argocd_namespace" {
  description = "Namespace Argo CD runs in. Created by layer 5-cluster, which owns it."
  type        = string
  default     = "argocd"
}

variable "argocd_version" {
  description = "Argo CD release tag to install."
  type        = string
  default     = "v3.4.4"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.argocd_version))
    error_message = "Must be a release tag such as v3.4.4. The installer refuses anything else."
  }
}

variable "argocd_manifest_sha256" {
  description = <<-EOT
    SHA-256 of the install manifest for argocd_version.

    Bootstrap downloads a large YAML file over the network and applies it with cluster-admin.
    A version tag is a mutable pointer at a URL; the digest is what makes substitution
    detectable. It must be updated in the same commit as the version, or the digest was
    never reviewed against the manifest it claims to describe.

    Mirrors argocd/install-manifest.sha256.
  EOT
  type        = string
  default     = "b0f9119821f2e19b852c842b9cb235eb9c3ef1549554fbda6aa5904e8d440eae"

  validation {
    condition     = can(regex("^[a-f0-9]{64}$", var.argocd_manifest_sha256))
    error_message = "Must be 64 lowercase hexadecimal characters."
  }
}

variable "wait_timeout" {
  description = "How long the installer waits for CRDs to become Established and Deployments Available."
  type        = string
  default     = "10m"
}

# ---------------------------------------------------------------------------
# The handover
# ---------------------------------------------------------------------------

variable "root_application_name" {
  description = "The app-of-apps. Everything else in the cluster descends from it."
  type        = string
  default     = "novashop-root"
}

variable "root_application_manifest" {
  description = "Manifest applied to create the root Application, relative to repository_root."
  type        = string
  default     = "argocd/application-ubuntu-k3s.yaml"
}

variable "project_manifest" {
  description = "Manifest applied to create the novashop AppProject, relative to repository_root."
  type        = string
  default     = "argocd/project.yaml"
}

variable "gitops_repo_url" {
  description = "Desired-state repository the root Application tracks."
  type        = string
  default     = "https://github.com/nguyenlpn2015/NovaShop-GitOps.git"
}

variable "gitops_target_revision" {
  description = <<-EOT
    Revision the root Application tracks.

    main, deliberately, and one of only two references in the platform that is not pinned to
    a commit SHA. Pinning the root Application would mean no GitOps change could ever take
    effect without editing the cluster. See ADR 003.
  EOT
  type        = string
  default     = "main"
}

variable "gitops_path" {
  description = "Path within the GitOps repository the root Application renders."
  type        = string
  default     = "clusters/ubuntu-k3s"
}

variable "project_name" {
  description = "AppProject the root Application belongs to. Applied by the bootstrap script, not reconciled by Argo CD."
  type        = string
  default     = "novashop"
}

# ---------------------------------------------------------------------------
# Repository registration
# ---------------------------------------------------------------------------

variable "repositories" {
  description = <<-EOT
    Repositories registered with Argo CD.

    Both are public, which is the whole reason this is safe to manage here: the Secret holds
    a url and a type and no credential. A repository Secret for a private repository would
    carry a token or an SSH key, and Terraform state stores those in plaintext — see
    ADR 010. A check block below refuses any key that looks like a credential.

    project is deliberately absent. Scoping a repository to a project restricts every other
    project from using it, which would break the novashop-platform Applications that render
    from the same repositories. Registering them unscoped matches the behaviour today:
    anonymous clone, available to all projects.
  EOT
  type = map(object({
    url  = string
    type = optional(string, "git")
  }))
  default = {
    "novashop" = {
      url = "https://github.com/nguyenlpn2015/NovaShop.git"
    }
    "novashop-gitops" = {
      url = "https://github.com/nguyenlpn2015/NovaShop-GitOps.git"
    }
  }

  validation {
    condition     = alltrue([for r in var.repositories : startswith(r.url, "https://")])
    error_message = "Only https URLs are registered here. An ssh:// URL implies a deploy key, which would place a credential in Terraform state."
  }
}

variable "manage_repository_registration" {
  description = "Register the repositories with Argo CD. Additive; nothing today depends on it."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Execution
# ---------------------------------------------------------------------------

variable "run_bootstrap" {
  description = <<-EOT
    Whether Terraform executes the installer and bootstrap scripts.

    Defaults to false. On a cluster that is already bootstrapped there is nothing to do, and
    the scripts wait for Deployments and rollouts — a long no-op with a real chance of
    surprising whoever ran `terraform apply` expecting a quick change.

    Set true on a fresh node or during recovery, which is where this layer earns its place.
  EOT
  type        = bool
  default     = false
}
