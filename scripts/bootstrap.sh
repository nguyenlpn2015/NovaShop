#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT
readonly ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
readonly WAIT_TIMEOUT="${WAIT_TIMEOUT:-10m}"
readonly WAIT_SECONDS="${WAIT_SECONDS:-600}"
readonly MINIMUM_KUBERNETES_MINOR=33
readonly ENVIRONMENTS=(development staging production)
ARGOCD_APPLICATION_MANIFEST="${ARGOCD_APPLICATION_MANIFEST:-${REPO_ROOT}/argocd/application.yaml}"
readonly ARGOCD_APPLICATION_MANIFEST
readonly ENABLE_PUBLIC_EDGE_VALIDATION="${ENABLE_PUBLIC_EDGE_VALIDATION:-false}"

KUBECTL=(kubectl)
if [[ -n "${KUBE_CONTEXT:-}" ]]; then
  KUBECTL+=(--context "${KUBE_CONTEXT}")
fi

log() {
  printf '[bootstrap] %s\n' "$*"
}

die() {
  printf '[bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

wait_for_resource() {
  local resource="$1"
  local namespace="$2"
  local elapsed=0

  until "${KUBECTL[@]}" get "${resource}" \
    --namespace "${namespace}" >/dev/null 2>&1; do
    if (( elapsed >= WAIT_SECONDS )); then
      die "Timed out waiting for ${resource} in ${namespace}."
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

wait_for_namespace() {
  local namespace="$1"
  local elapsed=0

  until "${KUBECTL[@]}" get namespace "${namespace}" >/dev/null 2>&1; do
    if (( elapsed >= WAIT_SECONDS )); then
      die "Timed out waiting for namespace ${namespace}."
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

ensure_runtime_secret() {
  local environment="$1"
  local namespace="novashop-${environment}"
  local secret_name="novashop-${environment}-secrets"
  local environment_prefix="${environment^^}"
  local database_variable="${environment_prefix}_DATABASE_URL"
  local redis_variable="${environment_prefix}_REDIS_URL"
  local database_url="${!database_variable:-${DATABASE_URL:-}}"
  local redis_url="${!redis_variable:-${REDIS_URL:-}}"

  if "${KUBECTL[@]}" get secret "${secret_name}" \
    --namespace "${namespace}" >/dev/null 2>&1; then
    log "Runtime Secret ${namespace}/${secret_name} already exists."
    return
  fi

  [[ -n "${database_url}" ]] \
    || die "${database_variable} or DATABASE_URL is required for ${secret_name}."
  [[ -n "${redis_url}" ]] \
    || die "${redis_variable} or REDIS_URL is required for ${secret_name}."

  "${KUBECTL[@]}" create secret generic "${secret_name}" \
    --namespace "${namespace}" \
    --from-literal=DATABASE_URL="${database_url}" \
    --from-literal=REDIS_URL="${redis_url}" \
    --dry-run=client \
    --output=yaml \
    | "${KUBECTL[@]}" apply \
        --server-side \
        --field-manager=novashop-runtime-bootstrap \
        -f -

  log "Created runtime Secret ${namespace}/${secret_name}."
}

main() {
  local server_minor
  local environment

  require_command kubectl
  require_command sed
  require_command sleep

  [[ -r "${ARGOCD_APPLICATION_MANIFEST}" ]] \
    || die "Argo CD Application manifest is not readable: ${ARGOCD_APPLICATION_MANIFEST}"

  "${KUBECTL[@]}" cluster-info >/dev/null
  log "Using Kubernetes context: $("${KUBECTL[@]}" config current-context)"

  server_minor="$(
    "${KUBECTL[@]}" get --raw=/version \
      | sed -n \
          's/.*"minor"[[:space:]]*:[[:space:]]*"\([0-9][0-9]*\).*/\1/p'
  )"
  [[ -n "${server_minor}" ]] || die "Unable to determine Kubernetes version."
  (( server_minor >= MINIMUM_KUBERNETES_MINOR )) \
    || die "Kubernetes 1.${MINIMUM_KUBERNETES_MINOR}+ is required."

  bash "${SCRIPT_DIR}/install-argocd.sh"

  log "Applying NovaShop Argo CD project and root application."
  "${KUBECTL[@]}" apply \
    --server-side \
    --field-manager=novashop-bootstrap \
    -f "${REPO_ROOT}/argocd/project.yaml" \
    -f "${ARGOCD_APPLICATION_MANIFEST}"

  wait_for_resource "applicationset/novashop" "${ARGOCD_NAMESPACE}"

  for environment in "${ENVIRONMENTS[@]}"; do
    wait_for_resource \
      "application/novashop-${environment}" \
      "${ARGOCD_NAMESPACE}"
    wait_for_namespace "novashop-${environment}"
    ensure_runtime_secret "${environment}"
  done

  for environment in "${ENVIRONMENTS[@]}"; do
    wait_for_resource "deployment/novashop-backend" "novashop-${environment}"
    wait_for_resource "deployment/novashop-frontend" "novashop-${environment}"
    "${KUBECTL[@]}" wait \
      --namespace "novashop-${environment}" \
      --for=condition=Available \
      deployment/novashop-backend \
      deployment/novashop-frontend \
      --timeout="${WAIT_TIMEOUT}"
  done

  if [[ "${ENABLE_PUBLIC_EDGE_VALIDATION}" == "true" ]]; then
    wait_for_resource \
      "application/novashop-cert-manager" \
      "${ARGOCD_NAMESPACE}"
    wait_for_resource \
      "application/novashop-certificates" \
      "${ARGOCD_NAMESPACE}"
    wait_for_namespace "cert-manager"

    "${KUBECTL[@]}" wait \
      --for=condition=Ready \
      clusterissuer/letsencrypt-production \
      --timeout="${WAIT_TIMEOUT}"

    for environment in "${ENVIRONMENTS[@]}"; do
      "${KUBECTL[@]}" wait \
        --namespace "novashop-${environment}" \
        --for=condition=Ready \
        "certificate/novashop-${environment}-tls" \
        --timeout="${WAIT_TIMEOUT}"
    done
  fi

  "${KUBECTL[@]}" get applications \
    --namespace "${ARGOCD_NAMESPACE}" \
    --selector=app.kubernetes.io/part-of=novashop
  log "NovaShop GitOps runtime is ready."
}

main "$@"
