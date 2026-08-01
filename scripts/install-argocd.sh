#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT
readonly ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
readonly ARGOCD_VERSION="${ARGOCD_VERSION:-v3.4.4}"
readonly ARGOCD_INSTALL_DIR="${ARGOCD_INSTALL_DIR:-${HOME}/.local/bin}"
readonly WAIT_TIMEOUT="${WAIT_TIMEOUT:-10m}"
readonly INSTALL_MANIFEST_DIGESTS="${INSTALL_MANIFEST_DIGESTS:-${REPO_ROOT}/argocd/install-manifest.sha256}"

KUBECTL=(kubectl)
if [[ -n "${KUBE_CONTEXT:-}" ]]; then
  KUBECTL+=(--context "${KUBE_CONTEXT}")
fi

TEMPORARY_DIRECTORY=""

log() {
  printf '[install-argocd] %s\n' "$*"
}

die() {
  printf '[install-argocd] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

remove_temporary_directory() {
  if [[ -n "${TEMPORARY_DIRECTORY}" \
    && -d "${TEMPORARY_DIRECTORY}" ]]; then
    rm -rf -- "${TEMPORARY_DIRECTORY}"
  fi
}

trap remove_temporary_directory EXIT

# Downloads the official installation manifest and verifies it against the
# digest reviewed in this repository. Bootstrap and disaster recovery must
# install exactly the control plane that was approved, even when the upstream
# host is unavailable or serving unexpected content.
fetch_verified_install_manifest() {
  local manifest_name="argo-cd-${ARGOCD_VERSION}-install.yaml"
  local manifest_path="${TEMPORARY_DIRECTORY}/${manifest_name}"
  local expected_digest

  [[ -r "${INSTALL_MANIFEST_DIGESTS}" ]] \
    || die "Pinned digest file is not readable: ${INSTALL_MANIFEST_DIGESTS}"

  expected_digest="$(
    awk -v name="${manifest_name}" \
      '$1 !~ /^#/ && $2 == name { print $1 }' \
      "${INSTALL_MANIFEST_DIGESTS}"
  )"
  [[ -n "${expected_digest}" ]] \
    || die "No pinned digest for ${ARGOCD_VERSION} in ${INSTALL_MANIFEST_DIGESTS}. Add one in a reviewed change before installing this version."

  curl --fail --silent --show-error --location \
    --output "${manifest_path}" \
    "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

  printf '%s  %s\n' "${expected_digest}" "${manifest_path}" \
    | sha256sum --check --status - \
    || die "Argo CD ${ARGOCD_VERSION} manifest failed digest verification. Refusing to apply unreviewed content."

  printf '%s' "${manifest_path}"
}

install_argocd_cli() {
  local architecture
  local asset
  local expected_checksum

  if command -v argocd >/dev/null 2>&1 \
    && argocd version --client 2>/dev/null | grep -Fq "${ARGOCD_VERSION#v}"; then
    log "Argo CD CLI ${ARGOCD_VERSION} is already installed."
    return
  fi

  case "$(uname -m)" in
    x86_64 | amd64)
      architecture="amd64"
      ;;
    aarch64 | arm64)
      architecture="arm64"
      ;;
    *)
      die "Unsupported architecture: $(uname -m)"
      ;;
  esac

  asset="argocd-linux-${architecture}"

  log "Downloading Argo CD CLI ${ARGOCD_VERSION}."
  curl --fail --silent --show-error --location \
    --output "${TEMPORARY_DIRECTORY}/${asset}" \
    "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/${asset}"
  curl --fail --silent --show-error --location \
    --output "${TEMPORARY_DIRECTORY}/cli_checksums.txt" \
    "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/cli_checksums.txt"

  expected_checksum="$(
    awk -v asset="${asset}" '$2 == asset { print $1 }' \
      "${TEMPORARY_DIRECTORY}/cli_checksums.txt"
  )"
  [[ -n "${expected_checksum}" ]] || die "Checksum not found for ${asset}."

  printf '%s  %s\n' \
    "${expected_checksum}" \
    "${TEMPORARY_DIRECTORY}/${asset}" \
    | sha256sum --check --status -

  mkdir -p -- "${ARGOCD_INSTALL_DIR}"
  install -m 0555 \
    "${TEMPORARY_DIRECTORY}/${asset}" \
    "${ARGOCD_INSTALL_DIR}/argocd"
  log "Installed Argo CD CLI at ${ARGOCD_INSTALL_DIR}/argocd."

  if [[ ":${PATH}:" != *":${ARGOCD_INSTALL_DIR}:"* ]]; then
    log "Add ${ARGOCD_INSTALL_DIR} to PATH before using the argocd command."
  fi
}

main() {
  local install_manifest

  require_command kubectl
  require_command curl
  require_command awk
  require_command grep
  require_command install
  require_command mktemp
  require_command sha256sum
  require_command uname

  [[ "${ARGOCD_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "ARGOCD_VERSION must be a release tag such as v3.4.4."

  TEMPORARY_DIRECTORY="$(mktemp -d)"

  "${KUBECTL[@]}" cluster-info >/dev/null
  log "Using Kubernetes context: $("${KUBECTL[@]}" config current-context)"

  "${KUBECTL[@]}" apply --server-side \
    --field-manager=novashop-bootstrap \
    -f "${REPO_ROOT}/argocd/namespace.yaml"

  install_manifest="$(fetch_verified_install_manifest)"
  log "Installing Argo CD ${ARGOCD_VERSION} from the verified pinned manifest."
  "${KUBECTL[@]}" apply \
    --namespace "${ARGOCD_NAMESPACE}" \
    --server-side \
    --force-conflicts \
    --field-manager=argocd-installer \
    -f "${install_manifest}"

  "${KUBECTL[@]}" wait \
    --namespace "${ARGOCD_NAMESPACE}" \
    --for=condition=Established \
    customresourcedefinition/applications.argoproj.io \
    customresourcedefinition/applicationsets.argoproj.io \
    customresourcedefinition/appprojects.argoproj.io \
    --timeout="${WAIT_TIMEOUT}"

  "${KUBECTL[@]}" wait \
    --namespace "${ARGOCD_NAMESPACE}" \
    --for=condition=Available \
    deployment \
    --all \
    --timeout="${WAIT_TIMEOUT}"

  "${KUBECTL[@]}" rollout status \
    statefulset/argocd-application-controller \
    --namespace "${ARGOCD_NAMESPACE}" \
    --timeout="${WAIT_TIMEOUT}"

  install_argocd_cli
  log "Argo CD installation is ready."
}

main "$@"
