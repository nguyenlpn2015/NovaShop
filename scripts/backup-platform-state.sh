#!/usr/bin/env bash

# Captures the cluster state that Git cannot reproduce.
#
# Everything else about NovaShop is declarative: the Helm chart, the environment
# values, the Argo CD applications, and the edge manifests all live in Git and
# are rebuilt by bootstrap. Two categories of material are not:
#
#   1. The issued TLS certificates and their private keys.
#   2. The ACME account key that authorises future issuance.
#
# Losing them is not merely inconvenient. Let's Encrypt limits duplicate
# certificates to five per identical hostname set per week, so a node rebuild
# combined with a rollback cycle can exhaust the quota and leave production
# without a usable certificate for days. Restoring this backup lets cert-manager
# adopt the existing certificates instead of requesting new ones.
#
# Runtime database and Redis credentials are excluded by default because they are
# reproducible from the platform environment file. Include them explicitly when
# that file is not part of the recovery plan.

set -Eeuo pipefail
IFS=$'\n\t'

readonly CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
readonly ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
readonly ENVIRONMENTS=(development staging production)
readonly ACME_ACCOUNT_SECRETS=(
  letsencrypt-production-account-key
  letsencrypt-staging-account-key
)

KUBECTL=(kubectl)
if [[ -n "${KUBE_CONTEXT:-}" ]]; then
  KUBECTL+=(--context "${KUBE_CONTEXT}")
fi

OUTPUT_DIRECTORY=""
INCLUDE_RUNTIME_SECRETS=false
EXPORTED_COUNT=0

log() {
  printf '[backup-platform-state] %s\n' "$*"
}

warn() {
  printf '[backup-platform-state] WARN: %s\n' "$*" >&2
}

die() {
  printf '[backup-platform-state] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

usage() {
  cat <<'EOF'
Usage: backup-platform-state.sh --output-dir DIR [--include-runtime-secrets]

  --output-dir DIR            Destination for the exported state. Created with
                              mode 0700; every file is written with mode 0600.
  --include-runtime-secrets   Also export the database and Redis Secrets.

Store the result outside the cluster and outside this repository. It contains
private keys.
EOF
}

# Exported Secrets must be reappliable into a different cluster instance.
# Cluster-assigned identity is removed, and ownerReferences in particular must go:
# a reference to a Certificate UID that no longer exists would make the garbage
# collector delete the restored Secret immediately.
export_secret() {
  local namespace="$1"
  local name="$2"
  local destination="$3"

  if ! "${KUBECTL[@]}" get secret "${name}" \
    --namespace "${namespace}" >/dev/null 2>&1; then
    warn "Secret ${namespace}/${name} does not exist; nothing exported."
    return 1
  fi

  "${KUBECTL[@]}" get secret "${name}" \
    --namespace "${namespace}" \
    --output=json \
    | jq --sort-keys '
        del(
          .metadata.resourceVersion,
          .metadata.uid,
          .metadata.creationTimestamp,
          .metadata.generation,
          .metadata.managedFields,
          .metadata.ownerReferences,
          .metadata.selfLink,
          .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration",
          .status
        )
      ' \
    >"${destination}"

  chmod 0600 "${destination}"
  EXPORTED_COUNT=$((EXPORTED_COUNT + 1))
  log "Exported ${namespace}/${name}."
}

write_inventory() {
  local inventory="${OUTPUT_DIRECTORY}/platform-state.txt"
  local environment

  {
    printf 'NovaShop platform state backup\n'
    printf 'created: %s\n' "$(date --iso-8601=seconds)"
    printf 'context: %s\n' "$("${KUBECTL[@]}" config current-context)"
    printf 'kubernetes: %s\n' \
      "$("${KUBECTL[@]}" version --output=json | jq -r '.serverVersion.gitVersion')"

    printf '\nArgo CD applications:\n'
    "${KUBECTL[@]}" get applications \
      --namespace "${ARGOCD_NAMESPACE}" \
      --selector=app.kubernetes.io/part-of=novashop \
      --output=custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision' \
      --no-headers 2>/dev/null || printf '  unavailable\n'

    printf '\nReconciled edge source paths:\n'
    for environment in "${ENVIRONMENTS[@]}"; do
      printf '  %s: %s\n' "${environment}" "$(
        "${KUBECTL[@]}" get "application/novashop-${environment}" \
          --namespace "${ARGOCD_NAMESPACE}" \
          --output=jsonpath='{range .spec.sources[*]}{.path}{"\n"}{end}' 2>/dev/null \
          | grep '^kubernetes/ingress/' \
          | head -n 1
      )"
    done

    printf '\nCertificate expiry:\n'
    for environment in "${ENVIRONMENTS[@]}"; do
      printf '  %s: %s\n' "${environment}" "$(
        "${KUBECTL[@]}" get secret "novashop-${environment}-tls" \
          --namespace "novashop-${environment}" \
          --output=jsonpath='{.data.tls\.crt}' 2>/dev/null \
          | base64 --decode 2>/dev/null \
          | openssl x509 -noout -enddate 2>/dev/null \
          | cut --delimiter='=' --fields=2- \
          || printf 'unavailable'
      )"
    done
  } >"${inventory}"

  chmod 0600 "${inventory}"
  log "Wrote inventory to ${inventory}."
}

main() {
  local environment
  local secret_name

  while (( $# > 0 )); do
    case "$1" in
      --output-dir)
        [[ $# -ge 2 ]] || die 'Option --output-dir requires a value.'
        OUTPUT_DIRECTORY="$2"
        shift
        ;;
      --include-runtime-secrets)
        INCLUDE_RUNTIME_SECRETS=true
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

  [[ -n "${OUTPUT_DIRECTORY}" ]] \
    || { usage >&2; die 'Option --output-dir is required.'; }

  "${KUBECTL[@]}" cluster-info >/dev/null
  log "Using Kubernetes context: $("${KUBECTL[@]}" config current-context)"

  mkdir -p -- "${OUTPUT_DIRECTORY}"
  chmod 0700 "${OUTPUT_DIRECTORY}"
  OUTPUT_DIRECTORY="$(cd -- "${OUTPUT_DIRECTORY}" && pwd)"

  for environment in "${ENVIRONMENTS[@]}"; do
    export_secret \
      "novashop-${environment}" \
      "novashop-${environment}-tls" \
      "${OUTPUT_DIRECTORY}/tls-${environment}.json" || true
  done

  for secret_name in "${ACME_ACCOUNT_SECRETS[@]}"; do
    export_secret \
      "${CERT_MANAGER_NAMESPACE}" \
      "${secret_name}" \
      "${OUTPUT_DIRECTORY}/acme-${secret_name}.json" || true
  done

  if [[ "${INCLUDE_RUNTIME_SECRETS}" == "true" ]]; then
    for environment in "${ENVIRONMENTS[@]}"; do
      export_secret \
        "novashop-${environment}" \
        "novashop-${environment}-secrets" \
        "${OUTPUT_DIRECTORY}/runtime-${environment}.json" || true
    done
  else
    log 'Runtime credential Secrets skipped; they are reproducible from the platform environment file.'
  fi

  write_inventory

  (( EXPORTED_COUNT > 0 )) \
    || die 'No Secret was exported. Verify the context and namespaces before relying on this backup.'

  log "Backup complete: ${EXPORTED_COUNT} Secret(s) in ${OUTPUT_DIRECTORY}."
  log 'Move this directory to protected storage outside the cluster.'
}

main "$@"
