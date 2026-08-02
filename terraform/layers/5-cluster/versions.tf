# Version pins for the cluster layer.
#
# The kubernetes provider is here and the helm provider deliberately is not. Helm releases
# belong to Argo CD; a helm provider in this layer would be the mechanism by which two
# controllers end up reconciling one release. See ADR 013.

terraform {
  required_version = "~> 1.9"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
  }
}
