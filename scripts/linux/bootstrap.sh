#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly REPO_ROOT
readonly NODE_IP="${NODE_IP:-10.10.1.45}"
readonly NODE_HOSTNAME="${NODE_HOSTNAME:-novashop-k3s}"
readonly CONFIGURE_HOSTNAME="${CONFIGURE_HOSTNAME:-false}"
readonly ENABLE_SYSTEM_UPGRADE="${ENABLE_SYSTEM_UPGRADE:-false}"
readonly ENABLE_UFW="${ENABLE_UFW:-false}"
readonly MANAGEMENT_CIDR="${MANAGEMENT_CIDR:-10.10.1.0/24}"
readonly KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
readonly PLATFORM_ENV_FILE="${PLATFORM_ENV_FILE:-/root/.novashop-platform.env}"

# shellcheck source=../lib/edge-phase.sh
source "${REPO_ROOT}/scripts/lib/edge-phase.sh"

log() {
  printf '[linux/bootstrap] %s\n' "$*"
}

die() {
  printf '[linux/bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

load_platform_environment() {
  local file_mode
  local file_owner

  [[ -f "${PLATFORM_ENV_FILE}" ]] \
    || die "Platform environment file is missing: ${PLATFORM_ENV_FILE}"
  [[ -r "${PLATFORM_ENV_FILE}" ]] \
    || die "Platform environment file is not readable: ${PLATFORM_ENV_FILE}"

  file_owner="$(stat --format='%u' "${PLATFORM_ENV_FILE}")"
  file_mode="$(stat --format='%a' "${PLATFORM_ENV_FILE}")"
  [[ "${file_owner}" == "0" ]] \
    || die "Platform environment file must be owned by root: ${PLATFORM_ENV_FILE}"
  (( (8#${file_mode} & 8#077) == 0 )) \
    || die "Platform environment file must not be accessible by group or others; run: chmod 600 ${PLATFORM_ENV_FILE}"

  log "Loading platform environment from ${PLATFORM_ENV_FILE}."
  set -a
  # shellcheck disable=SC1090
  source "${PLATFORM_ENV_FILE}"
  set +a

  [[ -n "${DATABASE_URL:-}" ]] \
    || die "DATABASE_URL is missing from ${PLATFORM_ENV_FILE}."
  [[ -n "${REDIS_URL:-}" ]] \
    || die "REDIS_URL is missing from ${PLATFORM_ENV_FILE}."
}

prepare_server() {
  # The pending-reboot gate runs before any package operation. Upgrading first
  # can create the reboot flag and abort a rerun through this script's own side
  # effect, which is the opposite of rerun-safe.
  if [[ -f /var/run/reboot-required ]]; then
    die 'Ubuntu requires a reboot. Reboot the VM, then rerun this script.'
  fi

  log 'Installing required packages.'
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install --yes \
    ca-certificates \
    curl \
    git \
    jq \
    openssh-client \
    tar \
    ufw

  # A distribution upgrade changes kernel and library versions and is therefore
  # neither idempotent nor safe to run implicitly during a recovery. It stays an
  # explicit operator decision taken outside an outage.
  if [[ "${ENABLE_SYSTEM_UPGRADE}" == "true" ]]; then
    log 'Applying system upgrades on request.'
    sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade --yes
    if [[ -f /var/run/reboot-required ]]; then
      die 'The system upgrade requires a reboot. Reboot the VM, then rerun this script.'
    fi
  else
    log 'System upgrade skipped. Set ENABLE_SYSTEM_UPGRADE=true to apply upgrades.'
  fi

  if swapon --show --noheadings | grep -q .; then
    die 'Active swap detected. Disable swap persistently, then rerun this script.'
  fi

  sudo timedatectl set-ntp true
  timedatectl show --property=NTPSynchronized --value

  if [[ "${CONFIGURE_HOSTNAME}" == "true" \
    && "$(hostnamectl --static)" != "${NODE_HOSTNAME}" ]]; then
    log "Setting hostname to ${NODE_HOSTNAME}."
    sudo hostnamectl set-hostname "${NODE_HOSTNAME}"
  fi
}

configure_firewall() {
  if [[ "${ENABLE_UFW}" != "true" ]]; then
    log 'UFW changes skipped. Set ENABLE_UFW=true after confirming console access.'
    return
  fi

  log "Configuring UFW for management network ${MANAGEMENT_CIDR}."
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow from "${MANAGEMENT_CIDR}" to any port 22 proto tcp
  sudo ufw allow from "${MANAGEMENT_CIDR}" to any port 6443 proto tcp
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw allow from 10.42.0.0/16
  sudo ufw allow from 10.43.0.0/16
  sudo ufw --force enable
  sudo ufw status verbose
}

verify_remote_repository() {
  local repository="$1"

  git ls-remote --exit-code "${repository}" refs/heads/main >/dev/null \
    || die "Repository is unavailable or has no main branch: ${repository}"
}

main() {
  local phase

  require_command apt-get
  require_command hostnamectl
  require_command sudo
  require_command swapon
  require_command stat
  require_command timedatectl

  load_platform_environment
  prepare_server
  require_command git
  configure_firewall

  verify_remote_repository 'https://github.com/nguyenlpn2015/NovaShop.git'
  verify_remote_repository 'https://github.com/nguyenlpn2015/NovaShop-GitOps.git'

  export NODE_IP
  bash "${SCRIPT_DIR}/install-k3s.sh"
  bash "${SCRIPT_DIR}/install-helm.sh"

  export KUBECONFIG
  kubectl --namespace kube-system rollout status \
    deployment/traefik \
    --timeout=5m

  bash "${SCRIPT_DIR}/install-argocd.sh"
  export PATH="${HOME}/.local/bin:${PATH}"

  log 'Bootstrapping NovaShop through the existing GitOps runtime.'
  export ARGOCD_APPLICATION_MANIFEST="${REPO_ROOT}/argocd/application-ubuntu-k3s.yaml"
  bash "${REPO_ROOT}/scripts/bootstrap.sh"

  # Verification follows whichever edge phase Git reconciled. Hard-coding the
  # expectation here would make a rerun fail after a reviewed rollback, even
  # though the cluster matched Git exactly.
  phase="$(detect_edge_phase)"
  log "Reconciled edge phase: ${phase}"
  export_verification_environment "${phase}" \
    || die "Edge phase '${phase}' cannot be verified. Inspect the GitOps repository."

  bash "${SCRIPT_DIR}/verify.sh"
  log "Deployment Target B is ready in the ${phase} edge phase."
}

main "$@"
