#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly K3S_VERSION="${K3S_VERSION:-v1.33.13+k3s1}"
readonly NODE_IP="${NODE_IP:-10.10.1.45}"
readonly KUBECONFIG_PATH="${KUBECONFIG_PATH:-${HOME}/.kube/config}"
readonly ALLOW_K3S_UPGRADE="${ALLOW_K3S_UPGRADE:-false}"

TEMPORARY_DIRECTORY=""

log() {
  printf '[install-k3s] %s\n' "$*"
}

die() {
  printf '[install-k3s] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

cleanup_temporary_directory() {
  if [[ -n "${TEMPORARY_DIRECTORY}" && -d "${TEMPORARY_DIRECTORY}" ]]; then
    rm -rf -- "${TEMPORARY_DIRECTORY}"
  fi
}

trap cleanup_temporary_directory EXIT

verify_platform() {
  [[ -r /etc/os-release ]] || die '/etc/os-release is unavailable.'

  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "22.04" ]] \
    || die "Ubuntu Server 22.04 is required; found ${PRETTY_NAME:-unknown}."

  ip -4 address show | grep -Fq "${NODE_IP}/" \
    || die "NODE_IP ${NODE_IP} is not assigned to this server."
}

configure_kubeconfig() {
  local kubeconfig_directory

  kubeconfig_directory="$(dirname -- "${KUBECONFIG_PATH}")"
  mkdir -p -- "${kubeconfig_directory}"
  sudo install \
    --owner="$(id -u)" \
    --group="$(id -g)" \
    --mode=0600 \
    /etc/rancher/k3s/k3s.yaml \
    "${KUBECONFIG_PATH}"

  log "User kubeconfig is ready at ${KUBECONFIG_PATH}."
}

wait_for_node_registration() {
  local deadline=$((SECONDS + 300))

  log 'Waiting for the k3s node to register.'
  while ! KUBECONFIG="${KUBECONFIG_PATH}" \
    kubectl get nodes --no-headers 2>/dev/null | grep -q .; do
    (( SECONDS < deadline )) \
      || die 'Timed out waiting for the k3s node to register.'
    sleep 2
  done
}

install_k3s() {
  local current_version=""
  local installer

  if command -v k3s >/dev/null 2>&1; then
    current_version="$(k3s --version | awk 'NR == 1 { print $3 }')"
    if [[ "${current_version}" == "${K3S_VERSION}" ]]; then
      log "k3s ${K3S_VERSION} is already installed."
      sudo systemctl enable --now k3s
      return
    fi

    [[ "${ALLOW_K3S_UPGRADE}" == "true" ]] \
      || die "Installed k3s is ${current_version}; set ALLOW_K3S_UPGRADE=true to reconcile ${K3S_VERSION}."
    log "Reconciling k3s ${current_version} to ${K3S_VERSION}."
  fi

  TEMPORARY_DIRECTORY="$(mktemp -d)"
  installer="${TEMPORARY_DIRECTORY}/install-k3s.sh"

  curl --fail --silent --show-error --location \
    https://get.k3s.io \
    --output "${installer}"
  chmod 0700 "${installer}"

  sudo env \
    INSTALL_K3S_VERSION="${K3S_VERSION}" \
    INSTALL_K3S_EXEC="server --node-ip=${NODE_IP} --advertise-address=${NODE_IP} --tls-san=${NODE_IP} --write-kubeconfig-mode=0640" \
    sh "${installer}"
}

main() {
  require_command awk
  require_command curl
  require_command grep
  require_command ip
  require_command mktemp
  require_command sleep
  require_command sudo
  require_command systemctl

  [[ "${K3S_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+\+k3s[0-9]+$ ]] \
    || die "K3S_VERSION must be a pinned release such as v1.33.13+k3s1."
  [[ "${NODE_IP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "NODE_IP must be an IPv4 address."

  verify_platform
  install_k3s

  sudo systemctl is-active --quiet k3s \
    || die 'k3s service is not active.'
  configure_kubeconfig

  wait_for_node_registration
  KUBECONFIG="${KUBECONFIG_PATH}" kubectl wait \
    --for=condition=Ready \
    node \
    --all \
    --timeout=5m
  KUBECONFIG="${KUBECONFIG_PATH}" kubectl get nodes -o wide
  log "k3s ${K3S_VERSION} is ready on ${NODE_IP}."
}

main "$@"
