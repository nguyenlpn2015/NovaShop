#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly HELM_VERSION="${HELM_VERSION:-v3.21.1}"
readonly INSTALL_DIRECTORY="${HELM_INSTALL_DIRECTORY:-/usr/local/bin}"

TEMPORARY_DIRECTORY=""

log() {
  printf '[install-helm] %s\n' "$*"
}

die() {
  printf '[install-helm] ERROR: %s\n' "$*" >&2
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

resolve_architecture() {
  case "$(uname -m)" in
    x86_64 | amd64)
      printf 'amd64'
      ;;
    aarch64 | arm64)
      printf 'arm64'
      ;;
    *)
      die "Unsupported architecture: $(uname -m)"
      ;;
  esac
}

main() {
  local architecture
  local archive
  local base_url

  require_command curl
  require_command grep
  require_command install
  require_command mktemp
  require_command sha256sum
  require_command sudo
  require_command tar
  require_command uname

  [[ "${HELM_VERSION}" =~ ^v3\.[0-9]+\.[0-9]+$ ]] \
    || die "HELM_VERSION must be a pinned Helm 3 release."

  if command -v helm >/dev/null 2>&1 \
    && helm version --short 2>/dev/null | grep -Fq "${HELM_VERSION}"; then
    log "Helm ${HELM_VERSION} is already installed."
    exit 0
  fi

  architecture="$(resolve_architecture)"
  archive="helm-${HELM_VERSION}-linux-${architecture}.tar.gz"
  base_url="https://get.helm.sh"
  TEMPORARY_DIRECTORY="$(mktemp -d)"

  log "Downloading Helm ${HELM_VERSION} for linux/${architecture}."
  curl --fail --silent --show-error --location \
    "${base_url}/${archive}" \
    --output "${TEMPORARY_DIRECTORY}/${archive}"
  curl --fail --silent --show-error --location \
    "${base_url}/${archive}.sha256sum" \
    --output "${TEMPORARY_DIRECTORY}/${archive}.sha256sum"

  (
    cd -- "${TEMPORARY_DIRECTORY}"
    sha256sum --check --status "${archive}.sha256sum"
    tar --extract --gzip --file="${archive}"
  )

  sudo install \
    --owner=root \
    --group=root \
    --mode=0755 \
    "${TEMPORARY_DIRECTORY}/linux-${architecture}/helm" \
    "${INSTALL_DIRECTORY}/helm"

  helm version --short
  log "Helm ${HELM_VERSION} is installed at ${INSTALL_DIRECTORY}/helm."
}

main "$@"
