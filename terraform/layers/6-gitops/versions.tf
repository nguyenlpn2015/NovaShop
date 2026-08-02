# Version pins for the GitOps bootstrap layer.
#
# The kubernetes provider is here for repository registration and for the data sources that
# validate the handover. The helm provider is not, and will not be: Helm releases are
# reconciled by Argo CD, which is the thing this layer hands control over to.

terraform {
  required_version = "~> 1.9"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
  }
}
