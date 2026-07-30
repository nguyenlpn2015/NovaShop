#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
readonly EXPECTED_NODE_IP="${NODE_IP:-10.10.1.45}"
readonly ENVIRONMENTS=(development staging production)

log() {
  printf '[linux/verify] %s\n' "$*"
}

die() {
  printf '[linux/verify] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

verify_application() {
  local environment="$1"
  local application="novashop-${environment}"
  local sync_status
  local health_status

  sync_status="$(
    kubectl get application "${application}" \
      --namespace argocd \
      --output=jsonpath='{.status.sync.status}'
  )"
  health_status="$(
    kubectl get application "${application}" \
      --namespace argocd \
      --output=jsonpath='{.status.health.status}'
  )"

  [[ "${sync_status}" == "Synced" ]] \
    || die "${application} sync status is ${sync_status:-unknown}."
  [[ "${health_status}" == "Healthy" ]] \
    || die "${application} health status is ${health_status:-unknown}."
}

main() {
  local environment
  local node_ip

  require_command argocd
  require_command helm
  require_command kubectl
  require_command systemctl

  [[ -r "${KUBECONFIG}" ]] || die "Kubeconfig is not readable: ${KUBECONFIG}"
  systemctl is-active --quiet k3s || die 'k3s service is not active.'

  kubectl cluster-info
  kubectl wait --for=condition=Ready node --all --timeout=5m
  node_ip="$(
    kubectl get node \
      --output=jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'
  )"
  [[ "${node_ip}" == "${EXPECTED_NODE_IP}" ]] \
    || die "Node IP is ${node_ip}; expected ${EXPECTED_NODE_IP}."

  kubectl --namespace kube-system rollout status \
    deployment/traefik \
    --timeout=5m
  kubectl --namespace argocd wait \
    --for=condition=Available \
    deployment \
    --all \
    --timeout=10m
  kubectl --namespace argocd rollout status \
    statefulset/argocd-application-controller \
    --timeout=10m

  for environment in "${ENVIRONMENTS[@]}"; do
    kubectl --namespace "novashop-${environment}" wait \
      --for=condition=Available \
      deployment/novashop-backend \
      deployment/novashop-frontend \
      --timeout=10m
    verify_application "${environment}"
  done

  kubectl get nodes -o wide
  kubectl get pods --all-namespaces
  kubectl get services --all-namespaces
  kubectl get ingress --all-namespaces
  kubectl get applications,applicationsets --namespace argocd
  helm list --all-namespaces

  if kubectl top nodes >/dev/null 2>&1; then
    kubectl top nodes
    kubectl top pods --all-namespaces
  else
    log 'Metrics API is not ready; inspect kube-system/metrics-server.'
  fi

  log 'All NovaShop applications are Synced and Healthy.'
}

main "$@"
