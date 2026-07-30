#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly REPO_ROOT
readonly KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"

log() {
  printf '[linux/install-argocd] %s\n' "$*"
}

die() {
  printf '[linux/install-argocd] ERROR: %s\n' "$*" >&2
  exit 1
}

main() {
  [[ -r "${KUBECONFIG}" ]] || die "Kubeconfig is not readable: ${KUBECONFIG}"
  command -v kubectl >/dev/null 2>&1 || die 'Required command not found: kubectl'

  kubectl cluster-info >/dev/null
  log 'Reconciling the pinned official Argo CD installation.'
  bash "${REPO_ROOT}/scripts/install-argocd.sh"

  export PATH="${HOME}/.local/bin:${PATH}"
  command -v argocd >/dev/null 2>&1 \
    || die 'Argo CD CLI was installed but is not available in PATH.'
  argocd version --client
  kubectl get pods --namespace argocd
  log 'Argo CD is ready.'
}

main "$@"
