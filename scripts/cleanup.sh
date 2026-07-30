#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
readonly ARGOCD_VERSION="${ARGOCD_VERSION:-v3.4.4}"
readonly WAIT_TIMEOUT="${WAIT_TIMEOUT:-10m}"
readonly ENVIRONMENTS=(development staging production)

KUBECTL=(kubectl)
if [[ -n "${KUBE_CONTEXT:-}" ]]; then
  KUBECTL+=(--context "${KUBE_CONTEXT}")
fi

CONFIRMED=false
INCLUDE_ARGOCD=false

log() {
  printf '[cleanup] %s\n' "$*"
}

die() {
  printf '[cleanup] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: cleanup.sh --confirm [--include-argocd]

  --confirm          Required acknowledgement for deleting NovaShop runtime.
  --include-argocd   Also remove the pinned Argo CD installation and namespace.
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
  || die "Refusing cleanup without --confirm."
command -v kubectl >/dev/null 2>&1 || die "Required command not found: kubectl"
command -v grep >/dev/null 2>&1 || die "Required command not found: grep"

"${KUBECTL[@]}" cluster-info >/dev/null
log "Using Kubernetes context: $("${KUBECTL[@]}" config current-context)"

if "${KUBECTL[@]}" api-resources \
  --api-group=argoproj.io \
  --output=name \
  | grep -qx 'applications.argoproj.io'; then
  "${KUBECTL[@]}" delete application novashop-root \
    --namespace "${ARGOCD_NAMESPACE}" \
    --ignore-not-found \
    --wait=true \
    --timeout="${WAIT_TIMEOUT}"

  "${KUBECTL[@]}" delete applicationset novashop \
    --namespace "${ARGOCD_NAMESPACE}" \
    --ignore-not-found \
    --wait=true \
    --timeout="${WAIT_TIMEOUT}"

  "${KUBECTL[@]}" delete application \
    --namespace "${ARGOCD_NAMESPACE}" \
    --selector=app.kubernetes.io/part-of=novashop \
    --ignore-not-found \
    --wait=true \
    --timeout="${WAIT_TIMEOUT}"

  "${KUBECTL[@]}" delete appproject novashop \
    --namespace "${ARGOCD_NAMESPACE}" \
    --ignore-not-found \
    --wait=true \
    --timeout="${WAIT_TIMEOUT}"
fi

for environment in "${ENVIRONMENTS[@]}"; do
  "${KUBECTL[@]}" delete namespace "novashop-${environment}" \
    --ignore-not-found \
    --wait=true \
    --timeout="${WAIT_TIMEOUT}"
done

if [[ "${INCLUDE_ARGOCD}" == "true" ]]; then
  log "Removing Argo CD ${ARGOCD_VERSION}."
  "${KUBECTL[@]}" delete \
    --namespace "${ARGOCD_NAMESPACE}" \
    --ignore-not-found \
    --wait=false \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
  "${KUBECTL[@]}" delete namespace "${ARGOCD_NAMESPACE}" \
    --ignore-not-found \
    --wait=true \
    --timeout="${WAIT_TIMEOUT}"
fi

log "Cleanup completed."
