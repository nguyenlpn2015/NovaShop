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
readonly TRAEFIK_NAMESPACE="${TRAEFIK_NAMESPACE:-kube-system}"

# These two variables are assertions, not instructions. The GitOps repository is
# the only place that decides which edge phase is active; bootstrap observes the
# reconciled state and refuses to continue when the operator's expectation and
# Git disagree. Leaving them unset lets bootstrap adopt whatever phase Git
# declares, which is what makes a rerun on a rebuilt node safe.
readonly ENABLE_TLS_VALIDATION="${ENABLE_TLS_VALIDATION:-}"
readonly EXPECTED_EDGE_SOURCE_PATH="${EXPECTED_EDGE_SOURCE_PATH:-}"

OBSERVED_EDGE_SOURCE_PATH=""
TLS_PHASE_ACTIVE=false

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

edge_source_path() {
  local application="$1"

  "${KUBECTL[@]}" get application "${application}" \
    --namespace "${ARGOCD_NAMESPACE}" \
    --output=jsonpath='{range .spec.sources[*]}{.path}{"\n"}{end}' \
    2>/dev/null \
    | grep '^kubernetes/ingress/' \
    | head -n 1
}

# Traefik belongs to k3s and is never modified here, but the public edge
# contract depends on its two entrypoints. Asserting them turns a silent
# routing failure after a node rebuild into an immediate, explicit error.
assert_traefik_edge() {
  local ports

  "${KUBECTL[@]}" --namespace "${TRAEFIK_NAMESPACE}" rollout status \
    deployment/traefik \
    --timeout="${WAIT_TIMEOUT}" >/dev/null \
    || die "Traefik is not available in ${TRAEFIK_NAMESPACE}."

  ports="$(
    "${KUBECTL[@]}" --namespace "${TRAEFIK_NAMESPACE}" get service traefik \
      --output=jsonpath='{range .spec.ports[*]}{.name}{"\n"}{end}'
  )"

  grep --fixed-strings --line-regexp --quiet web <<<"${ports}" \
    || die "Traefik has no 'web' entrypoint; HTTP routing and ACME HTTP-01 renewal cannot work."
  grep --fixed-strings --line-regexp --quiet websecure <<<"${ports}" \
    || die "Traefik has no 'websecure' entrypoint; HTTPS termination cannot work."

  log 'Traefik exposes the web and websecure entrypoints.'
}

tls_phase_is_reconciled() {
  "${KUBECTL[@]}" get application novashop-certificates \
    --namespace "${ARGOCD_NAMESPACE}" >/dev/null 2>&1
}

# Reconciles the operator's expectation with the reconciled desired state. A
# disagreement means bootstrap was invoked for a different phase than the one
# Git declares, which must stop before any TLS assertion is attempted.
resolve_edge_expectations() {
  OBSERVED_EDGE_SOURCE_PATH="$(edge_source_path 'novashop-production')"

  if [[ -z "${OBSERVED_EDGE_SOURCE_PATH}" ]]; then
    log 'No edge phase is reconciled; skipping edge and TLS assertions.'
  else
    log "Reconciled edge phase: ${OBSERVED_EDGE_SOURCE_PATH}"
    if [[ -n "${EXPECTED_EDGE_SOURCE_PATH}" \
      && "${EXPECTED_EDGE_SOURCE_PATH}" != "${OBSERVED_EDGE_SOURCE_PATH}" ]]; then
      die "Expected edge phase ${EXPECTED_EDGE_SOURCE_PATH} but GitOps reconciled ${OBSERVED_EDGE_SOURCE_PATH}. Resolve the disagreement in Git, not here."
    fi
    assert_traefik_edge
  fi

  if tls_phase_is_reconciled; then
    TLS_PHASE_ACTIVE=true
  else
    TLS_PHASE_ACTIVE=false
  fi

  if [[ -n "${ENABLE_TLS_VALIDATION}" \
    && "${ENABLE_TLS_VALIDATION}" != "${TLS_PHASE_ACTIVE}" ]]; then
    die "ENABLE_TLS_VALIDATION=${ENABLE_TLS_VALIDATION} disagrees with the reconciled state (certificates application present: ${TLS_PHASE_ACTIVE})."
  fi

  log "TLS phase active: ${TLS_PHASE_ACTIVE}"
}

wait_for_application_ready() {
  local application="$1"
  local elapsed=0
  local state

  until state="$(
    "${KUBECTL[@]}" get application "${application}" \
      --namespace "${ARGOCD_NAMESPACE}" \
      --output=jsonpath='{.status.sync.status}/{.status.health.status}' \
      2>/dev/null
  )" && [[ "${state}" == "Synced/Healthy" ]]; do
    if (( elapsed >= WAIT_SECONDS )); then
      die "Timed out waiting for ${application}; current state: ${state:-unknown}."
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

# A Secret that exists but is missing a key satisfies a presence check while
# leaving workloads unable to start. Recovery must detect that state instead of
# reporting success.
runtime_secret_is_complete() {
  local namespace="$1"
  local secret_name="$2"
  local key

  for key in DATABASE_URL REDIS_URL; do
    "${KUBECTL[@]}" get secret "${secret_name}" \
      --namespace "${namespace}" \
      --output="jsonpath={.data.${key}}" 2>/dev/null \
      | grep --quiet . \
      || return 1
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
    runtime_secret_is_complete "${namespace}" "${secret_name}" \
      || die "Runtime Secret ${namespace}/${secret_name} exists but is missing DATABASE_URL or REDIS_URL. Delete it and rerun with the correct values."
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
  require_command grep
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

  resolve_edge_expectations

  for environment in "${ENVIRONMENTS[@]}"; do
    wait_for_resource "deployment/novashop-backend" "novashop-${environment}"
    wait_for_resource "deployment/novashop-frontend" "novashop-${environment}"
    "${KUBECTL[@]}" wait \
      --namespace "novashop-${environment}" \
      --for=condition=Available \
      deployment/novashop-backend \
      deployment/novashop-frontend \
      --timeout="${WAIT_TIMEOUT}"
    wait_for_application_ready "novashop-${environment}"

    if [[ -n "${OBSERVED_EDGE_SOURCE_PATH}" ]]; then
      wait_for_resource \
        "ingress/novashop-public-http" \
        "novashop-${environment}"
      # Every environment must reconcile the same phase; a split leaves one
      # environment enforcing HTTPS while another serves plaintext.
      [[ "$(edge_source_path "novashop-${environment}")" \
        == "${OBSERVED_EDGE_SOURCE_PATH}" ]] \
        || die "novashop-${environment} reconciled a different edge phase than novashop-production."
    fi
  done

  wait_for_application_ready "novashop-root"

  if [[ "${TLS_PHASE_ACTIVE}" == "true" ]]; then
    wait_for_resource \
      "application/novashop-cert-manager" \
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
