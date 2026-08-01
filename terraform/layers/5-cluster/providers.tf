# Provider configuration.
#
# The admin kubeconfig is /etc/rancher/k3s/k3s.yaml at mode 0600, so this runs as root on
# the node or against a copy the operator holds. It is a cluster-admin credential and is
# never committed.
#
# Unlike every other layer, plan here needs a reachable cluster: this layer reads live state
# through data sources in order to assert prerequisites. `terraform validate` still needs
# nothing, which is why CI can validate it without a cluster.

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}
