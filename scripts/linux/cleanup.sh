#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly REPO_ROOT
readonly KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"

CONFIRMED=false
INCLUDE_ARGOCD=false
UNINSTALL_K3S=false
CONFIRM_K3S_UNINSTALL=false

log() {
  printf '[linux/cleanup] %s\n' "$*"
}

die() {
  printf '[linux/cleanup] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  cleanup.sh --confirm [--include-argocd]
  cleanup.sh --confirm --uninstall-k3s --confirm-k3s-uninstall

Options:
  --confirm                 Required acknowledgement for deleting NovaShop.
  --include-argocd          Also remove Argo CD from the cluster.
  --uninstall-k3s           Remove the entire k3s installation and local data.
  --confirm-k3s-uninstall   Second acknowledgement required with --uninstall-k3s.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --confirm)
      CONFIRMED=true
      ;;
    --include-argocd)
      INCLUDE_ARGOCD=true
      ;;
    --uninstall-k3s)
      UNINSTALL_K3S=true
      ;;
    --confirm-k3s-uninstall)
      CONFIRM_K3S_UNINSTALL=true
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "Unknown argument: $1"
      ;;
  esac
  shift
done

[[ "${CONFIRMED}" == "true" ]] \
  || die 'Refusing cleanup without --confirm.'
export KUBECONFIG

cleanup_arguments=(--confirm)
if [[ "${INCLUDE_ARGOCD}" == "true" ]]; then
  cleanup_arguments+=(--include-argocd)
fi

if systemctl is-active --quiet k3s; then
  bash "${REPO_ROOT}/scripts/cleanup.sh" "${cleanup_arguments[@]}"
else
  log 'k3s is not active; Kubernetes resource cleanup skipped.'
fi

if [[ "${UNINSTALL_K3S}" == "true" ]]; then
  [[ "${CONFIRM_K3S_UNINSTALL}" == "true" ]] \
    || die 'Refusing k3s uninstall without --confirm-k3s-uninstall.'
  [[ -x /usr/local/bin/k3s-uninstall.sh ]] \
    || die 'Official k3s uninstall script was not found.'

  log 'Uninstalling k3s and deleting its node-local cluster data.'
  sudo /usr/local/bin/k3s-uninstall.sh
fi

log 'Cleanup completed.'
