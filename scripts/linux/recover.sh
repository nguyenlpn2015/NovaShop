#!/usr/bin/env bash

# Disaster recovery entry point for Deployment Target B.
#
# Rebuilds the platform on a replacement VM from the GitOps repository, the
# existing public DNS records, and an optional certificate backup. Recovery is
# not a variant of bootstrap: it must refuse to start when a precondition is
# missing, because discovering a missing input halfway through leaves production
# in a worse state than before.
#
# Preconditions are checked in full and reported together, so an operator fixes
# everything in one pass instead of one failure per attempt.
#
# What this script assumes already exists:
#   - a reachable NovaShop and NovaShop-GitOps repository;
#   - public DNS records that resolve to this node;
#   - the platform environment file holding the runtime credentials;
#   - optionally, a backup produced by scripts/backup-platform-state.sh.
#
# Without a backup, cert-manager requests new certificates. That is supported but
# must be acknowledged explicitly, because Let's Encrypt allows only five
# duplicate certificates per hostname set per week.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly REPO_ROOT
readonly NODE_IP="${NODE_IP:-10.10.1.45}"
readonly KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
readonly PLATFORM_ENV_FILE="${PLATFORM_ENV_FILE:-/root/.novashop-platform.env}"
readonly TRAEFIK_NAMESPACE="${TRAEFIK_NAMESPACE:-kube-system}"
readonly WAIT_TIMEOUT="${WAIT_TIMEOUT:-10m}"
readonly APP_REPOSITORY="${APP_REPOSITORY:-https://github.com/nguyenlpn2015/NovaShop.git}"
readonly GITOPS_REPOSITORY="${GITOPS_REPOSITORY:-https://github.com/nguyenlpn2015/NovaShop-GitOps.git}"
readonly PUBLIC_HOSTS=(
  novashop.smartdev.vn
  api.novashop.smartdev.vn
  staging.novashop.smartdev.vn
  api.staging.novashop.smartdev.vn
  dev.novashop.smartdev.vn
  api.dev.novashop.smartdev.vn
)

# shellcheck source=../lib/edge-phase.sh
source "${REPO_ROOT}/scripts/lib/edge-phase.sh"

BACKUP_DIRECTORY=""
ACCEPT_CERTIFICATE_REISSUE=false
SKIP_VERIFY=false
PRECONDITION_FAILURES=0

log() {
  printf '[linux/recover] %s\n' "$*"
}

die() {
  printf '[linux/recover] ERROR: %s\n' "$*" >&2
  exit 1
}

precondition_ok() {
  printf '[linux/recover] OK: %s\n' "$1"
}

precondition_failed() {
  PRECONDITION_FAILURES=$((PRECONDITION_FAILURES + 1))
  printf '[linux/recover] MISSING: %s\n' "$1" >&2
  if [[ -n "${2:-}" ]]; then
    printf '[linux/recover]          %s\n' "$2" >&2
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

usage() {
  cat <<'EOF'
Usage:
  recover.sh --from-backup DIR [--skip-verify]
  recover.sh --accept-certificate-reissue [--skip-verify]

  --from-backup DIR              Certificate backup from backup-platform-state.sh.
  --accept-certificate-reissue   Proceed without a backup and let cert-manager
                                 request new certificates, consuming Let's
                                 Encrypt issuance quota.
  --skip-verify                  Skip the post-recovery verification run.
EOF
}

check_platform_environment_file() {
  local file_owner
  local file_mode

  if [[ ! -f "${PLATFORM_ENV_FILE}" ]]; then
    precondition_failed \
      "platform environment file ${PLATFORM_ENV_FILE}" \
      'Restore it from protected storage; it holds DATABASE_URL and REDIS_URL.'
    return
  fi

  file_owner="$(stat --format='%u' "${PLATFORM_ENV_FILE}")"
  file_mode="$(stat --format='%a' "${PLATFORM_ENV_FILE}")"

  if [[ "${file_owner}" != "0" ]]; then
    precondition_failed \
      "platform environment file is owned by root" \
      "Run: chown root:root ${PLATFORM_ENV_FILE}"
    return
  fi

  if (( (8#${file_mode} & 8#077) != 0 )); then
    precondition_failed \
      "platform environment file is not group or world accessible" \
      "Run: chmod 600 ${PLATFORM_ENV_FILE}"
    return
  fi

  # The `export ` prefix is optional and must be tolerated.
  #
  # This check grepped '^[[:space:]]*DATABASE_URL=' and the real file declares
  # `export DATABASE_URL=`, so it matched nothing. Recovery aborted at its first
  # precondition on a completely healthy platform — meaning the disaster recovery script
  # could never have run, and nobody knew because it had never been run.
  #
  # The same mismatch was found and fixed in configure-datastores.sh earlier. Finding it a
  # second time in a different script is the argument for exercising recovery rather than
  # reviewing it.
  if ! grep --quiet --extended-regexp '^[[:space:]]*(export[[:space:]]+)?DATABASE_URL=' "${PLATFORM_ENV_FILE}" \
    || ! grep --quiet --extended-regexp '^[[:space:]]*(export[[:space:]]+)?REDIS_URL=' "${PLATFORM_ENV_FILE}"; then
    precondition_failed \
      "platform environment file declares DATABASE_URL and REDIS_URL" \
      "Both variables are required to recreate the runtime Secrets."
    return
  fi

  precondition_ok "platform environment file ${PLATFORM_ENV_FILE}"
}

check_repository_reachable() {
  local repository="$1"

  if git ls-remote --exit-code "${repository}" refs/heads/main >/dev/null 2>&1; then
    precondition_ok "repository reachable: ${repository}"
  else
    precondition_failed \
      "repository reachable: ${repository}" \
      'Recovery reads desired state from Git and cannot proceed without it.'
  fi
}

# DNS is treated as pre-existing infrastructure. Recovery does not create records,
# but ACME HTTP-01 validation and every public route depend on them resolving to
# this node, so a mismatch is reported before k3s is touched.
check_public_dns() {
  local hostname
  local resolved
  local failures=0

  for hostname in "${PUBLIC_HOSTS[@]}"; do
    resolved="$(
      getent ahostsv4 "${hostname}" 2>/dev/null \
        | awk 'NR == 1 { print $1 }' \
        || true
    )"

    if [[ -z "${resolved}" ]]; then
      precondition_failed "DNS resolves ${hostname}" 'No A record was returned.'
      failures=$((failures + 1))
      continue
    fi

    if [[ "${resolved}" != "${NODE_IP}" ]]; then
      log "NOTE: ${hostname} resolves to ${resolved}, not ${NODE_IP}. This is expected behind a proxy or NAT."
    fi
  done

  if (( failures == 0 )); then
    precondition_ok 'public DNS records resolve'
  fi
}

check_certificate_material() {
  if [[ -n "${BACKUP_DIRECTORY}" ]]; then
    if [[ ! -d "${BACKUP_DIRECTORY}" ]]; then
      precondition_failed \
        "certificate backup directory ${BACKUP_DIRECTORY}" \
        'The path does not exist.'
      return
    fi

    if ! compgen -G "${BACKUP_DIRECTORY}/tls-*.json" >/dev/null; then
      precondition_failed \
        "certificate backup contains exported TLS Secrets" \
        "No tls-*.json file was found in ${BACKUP_DIRECTORY}."
      return
    fi

    precondition_ok "certificate backup ${BACKUP_DIRECTORY}"
    return
  fi

  if [[ "${ACCEPT_CERTIFICATE_REISSUE}" == "true" ]]; then
    log 'WARNING: no certificate backup supplied. cert-manager will request new certificates and consume issuance quota.'
    precondition_ok 'certificate reissue acknowledged'
    return
  fi

  precondition_failed \
    'certificate material is available' \
    'Supply --from-backup DIR, or accept new issuance with --accept-certificate-reissue.'
}

run_preconditions() {
  log 'Checking recovery preconditions.'
  check_platform_environment_file
  check_repository_reachable "${APP_REPOSITORY}"
  check_repository_reachable "${GITOPS_REPOSITORY}"
  check_public_dns
  check_certificate_material

  (( PRECONDITION_FAILURES == 0 )) \
    || die "${PRECONDITION_FAILURES} precondition(s) are unmet. Resolve them and rerun."
  log 'All preconditions are satisfied.'
}

load_platform_environment() {
  log "Loading platform environment from ${PLATFORM_ENV_FILE}."
  set -a
  # shellcheck disable=SC1090
  source "${PLATFORM_ENV_FILE}"
  set +a
}

rebuild_cluster() {
  export NODE_IP
  bash "${SCRIPT_DIR}/install-k3s.sh"
  bash "${SCRIPT_DIR}/install-helm.sh"

  export KUBECONFIG
  kubectl --namespace "${TRAEFIK_NAMESPACE}" rollout status \
    deployment/traefik \
    --timeout="${WAIT_TIMEOUT}"

  bash "${SCRIPT_DIR}/install-argocd.sh"
  export PATH="${HOME}/.local/bin:${PATH}"
}

restore_certificate_material() {
  [[ -n "${BACKUP_DIRECTORY}" ]] || return 0

  # Restoration happens between the Argo CD install and the GitOps bootstrap so
  # cert-manager adopts the existing certificates on its first reconciliation.
  log 'Restoring certificate material before GitOps reconciliation.'
  bash "${REPO_ROOT}/scripts/restore-platform-state.sh" \
    --input-dir "${BACKUP_DIRECTORY}"
}

# Application data is restored before Argo CD reconciles, for a reason that is easy to miss:
# the backend's /ready probe checks that PostgreSQL is *reachable*, not that it holds data.
# Skip this and the pods go Ready, every Application reports Healthy, no alert fires, and the
# application serves an empty database.
restore_datastore_contents() {
  [[ -n "${BACKUP_DIRECTORY}" ]] || return 0

  if [[ ! -f "${BACKUP_DIRECTORY}/manifest.txt" ]]; then
    log 'No datastore backup in this set; skipping. Certificate material is restored separately.'
    return 0
  fi

  log 'Verifying the datastore backup before restoring it.'
  bash "${REPO_ROOT}/scripts/verify-backup.sh" "${BACKUP_DIRECTORY}" --skip-age     || die 'The datastore backup failed verification. Restore aborted before any change.'

  log 'Restoring datastore contents.'
  bash "${REPO_ROOT}/scripts/restore-datastores.sh" --from "${BACKUP_DIRECTORY}" --force
}

reconcile_desired_state() {
  log 'Reconciling NovaShop from the GitOps repository.'
  export ARGOCD_APPLICATION_MANIFEST="${REPO_ROOT}/argocd/application-ubuntu-k3s.yaml"
  bash "${REPO_ROOT}/scripts/bootstrap.sh"
}

verify_recovery() {
  local phase

  if [[ "${SKIP_VERIFY}" == "true" ]]; then
    log 'Verification skipped on request.'
    return
  fi

  phase="$(detect_edge_phase)"
  log "Reconciled edge phase: ${phase}"
  export_verification_environment "${phase}" \
    || die "Edge phase '${phase}' cannot be verified. Inspect the GitOps repository."

  bash "${SCRIPT_DIR}/verify.sh"
}

main() {
  while (( $# > 0 )); do
    case "$1" in
      --from-backup)
        [[ $# -ge 2 ]] || die 'Option --from-backup requires a value.'
        BACKUP_DIRECTORY="$2"
        shift
        ;;
      --accept-certificate-reissue)
        ACCEPT_CERTIFICATE_REISSUE=true
        ;;
      --skip-verify)
        SKIP_VERIFY=true
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

  require_command awk
  require_command getent
  require_command git
  require_command grep
  require_command kubectl
  require_command stat

  if [[ -n "${BACKUP_DIRECTORY}" && "${ACCEPT_CERTIFICATE_REISSUE}" == "true" ]]; then
    die 'Choose either --from-backup or --accept-certificate-reissue, not both.'
  fi

  run_preconditions
  load_platform_environment
  rebuild_cluster
  restore_certificate_material
  restore_datastore_contents
  reconcile_desired_state
  verify_recovery

  log 'Recovery complete.'
}

main "$@"
