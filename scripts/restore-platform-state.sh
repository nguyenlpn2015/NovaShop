#!/usr/bin/env bash

# Restores the certificate material captured by backup-platform-state.sh.
#
# Ordering is the whole point of this script. It must run after Argo CD is
# installed but BEFORE the GitOps root application reconciles cert-manager and
# the Certificate resources. When cert-manager finds a Secret that already holds
# a valid certificate matching the Certificate spec, it adopts it and schedules a
# normal renewal instead of requesting a new one. Running this after cert-manager
# has already reconciled wastes Let's Encrypt issuance quota that a subsequent
# rollback may need.
#
# The target namespaces are created here for the same reason: a Secret cannot be
# placed in a namespace that does not exist yet, and waiting for Argo CD to create
# them would mean waiting until after cert-manager has acted. Argo CD adopts these
# namespaces on its next sync.

set -Eeuo pipefail
IFS=$'\n\t'

readonly CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
readonly ENVIRONMENTS=(development staging production)

KUBECTL=(kubectl)
if [[ -n "${KUBE_CONTEXT:-}" ]]; then
  KUBECTL+=(--context "${KUBE_CONTEXT}")
fi

INPUT_DIRECTORY=""
FORCE=false
RESTORED_COUNT=0

log() {
  printf '[restore-platform-state] %s\n' "$*"
}

warn() {
  printf '[restore-platform-state] WARN: %s\n' "$*" >&2
}

die() {
  printf '[restore-platform-state] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

usage() {
  cat <<'EOF'
Usage: restore-platform-state.sh --input-dir DIR [--force]

  --input-dir DIR   Directory produced by backup-platform-state.sh.
  --force           Overwrite Secrets that already exist in the cluster.

Run after scripts/install-argocd.sh and before scripts/bootstrap.sh.
EOF
}

ensure_namespace() {
  local namespace="$1"

  if "${KUBECTL[@]}" get namespace "${namespace}" >/dev/null 2>&1; then
    return
  fi

  "${KUBECTL[@]}" create namespace "${namespace}" \
    --dry-run=client \
    --output=yaml \
    | "${KUBECTL[@]}" apply \
        --server-side \
        --field-manager=novashop-restore \
        -f -
  log "Created namespace ${namespace}."
}

restore_secret() {
  local source_file="$1"
  local namespace
  local name

  [[ -f "${source_file}" ]] || return 0

  namespace="$(jq -r '.metadata.namespace' "${source_file}")"
  name="$(jq -r '.metadata.name' "${source_file}")"

  [[ -n "${namespace}" && "${namespace}" != "null" ]] \
    || die "Backup file has no namespace: ${source_file}"
  [[ -n "${name}" && "${name}" != "null" ]] \
    || die "Backup file has no name: ${source_file}"

  ensure_namespace "${namespace}"

  if "${KUBECTL[@]}" get secret "${name}" \
    --namespace "${namespace}" >/dev/null 2>&1; then
    if [[ "${FORCE}" != "true" ]]; then
      warn "Secret ${namespace}/${name} already exists; left untouched. Use --force to overwrite."
      return 0
    fi
    warn "Overwriting existing Secret ${namespace}/${name} on request."
  fi

  "${KUBECTL[@]}" apply \
    --server-side \
    --force-conflicts \
    --field-manager=novashop-restore \
    -f "${source_file}" >/dev/null

  RESTORED_COUNT=$((RESTORED_COUNT + 1))
  log "Restored ${namespace}/${name}."
}

# A restored certificate that has already expired is worse than none: cert-manager
# would still adopt the Secret and the edge would serve an untrusted chain until
# renewal completes. The operator is told explicitly.
report_certificate_validity() {
  local source_file="$1"
  local name
  local not_after

  [[ -f "${source_file}" ]] || return 0

  name="$(jq -r '.metadata.name' "${source_file}")"
  not_after="$(
    jq -r '.data."tls.crt" // empty' "${source_file}" \
      | base64 --decode 2>/dev/null \
      | openssl x509 -noout -enddate 2>/dev/null \
      | cut --delimiter='=' --fields=2- \
      || true
  )"

  if [[ -z "${not_after}" ]]; then
    warn "${name}: certificate expiry could not be read from the backup."
    return 0
  fi

  if openssl x509 -noout -checkend 0 \
    -in <(jq -r '.data."tls.crt"' "${source_file}" | base64 --decode) \
    >/dev/null 2>&1; then
    log "${name}: certificate is valid until ${not_after}."
  else
    warn "${name}: certificate expired on ${not_after}; cert-manager will reissue and consume issuance quota."
  fi
}

main() {
  local environment
  local source_file

  while (( $# > 0 )); do
    case "$1" in
      --input-dir)
        [[ $# -ge 2 ]] || die 'Option --input-dir requires a value.'
        INPUT_DIRECTORY="$2"
        shift
        ;;
      --force)
        FORCE=true
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

  require_command kubectl
  require_command jq
  require_command base64
  require_command openssl

  [[ -n "${INPUT_DIRECTORY}" ]] \
    || { usage >&2; die 'Option --input-dir is required.'; }
  [[ -d "${INPUT_DIRECTORY}" ]] \
    || die "Input directory does not exist: ${INPUT_DIRECTORY}"
  INPUT_DIRECTORY="$(cd -- "${INPUT_DIRECTORY}" && pwd)"

  "${KUBECTL[@]}" cluster-info >/dev/null
  log "Using Kubernetes context: $("${KUBECTL[@]}" config current-context)"

  ensure_namespace "${CERT_MANAGER_NAMESPACE}"

  for source_file in "${INPUT_DIRECTORY}"/acme-*.json; do
    restore_secret "${source_file}"
  done

  for environment in "${ENVIRONMENTS[@]}"; do
    source_file="${INPUT_DIRECTORY}/tls-${environment}.json"
    report_certificate_validity "${source_file}"
    restore_secret "${source_file}"
  done

  for environment in "${ENVIRONMENTS[@]}"; do
    restore_secret "${INPUT_DIRECTORY}/runtime-${environment}.json"
  done

  (( RESTORED_COUNT > 0 )) \
    || warn 'No Secret was restored. cert-manager will request new certificates.'

  log "Restore complete: ${RESTORED_COUNT} Secret(s)."
  log 'Run scripts/bootstrap.sh next so Argo CD adopts the restored material.'
}

main "$@"
