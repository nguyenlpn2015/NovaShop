#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
readonly ARGOCD_LOCAL_PORT="${ARGOCD_LOCAL_PORT:-8080}"
readonly ARGOCD_BIND_ADDRESS="${ARGOCD_BIND_ADDRESS:-127.0.0.1}"

KUBECTL=(kubectl)
if [[ -n "${KUBE_CONTEXT:-}" ]]; then
  KUBECTL+=(--context "${KUBE_CONTEXT}")
fi

die() {
  printf '[port-forward] ERROR: %s\n' "$*" >&2
  exit 1
}

command -v kubectl >/dev/null 2>&1 || die "Required command not found: kubectl"
command -v curl >/dev/null 2>&1 || die "Required command not found: curl"

"${KUBECTL[@]}" get service argocd-server \
  --namespace "${ARGOCD_NAMESPACE}" >/dev/null

if curl --insecure --fail --silent --show-error \
  "https://${ARGOCD_BIND_ADDRESS}:${ARGOCD_LOCAL_PORT}/healthz" \
  >/dev/null 2>&1; then
  printf '[port-forward] Argo CD is already available at https://%s:%s\n' \
    "${ARGOCD_BIND_ADDRESS}" \
    "${ARGOCD_LOCAL_PORT}"
  exit 0
fi

printf '[port-forward] Argo CD: https://%s:%s\n' \
  "${ARGOCD_BIND_ADDRESS}" \
  "${ARGOCD_LOCAL_PORT}"
printf '[port-forward] Press Ctrl+C to stop the port forward.\n'

exec "${KUBECTL[@]}" port-forward \
  --namespace "${ARGOCD_NAMESPACE}" \
  --address "${ARGOCD_BIND_ADDRESS}" \
  service/argocd-server \
  "${ARGOCD_LOCAL_PORT}:443"
