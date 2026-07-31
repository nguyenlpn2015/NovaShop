#!/usr/bin/env bash

# Cross-repository revision validation.
#
# NovaShop-GitOps pins immutable NovaShop revisions for the Helm chart, the
# edge manifests, and the cert-manager manifests. A pin that is not reachable
# from the NovaShop default branch survives only as long as the branch that
# carries it. Deleting that branch makes the commit unreachable, GitHub
# eventually garbage-collects it, and every Argo CD Application that references
# it stops rendering. Bootstrap and disaster recovery then fail with no prior
# warning. This script makes that condition a merge-blocking error.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT
readonly APP_REPOSITORY="${APP_REPOSITORY:-https://github.com/nguyenlpn2015/NovaShop.git}"
readonly GITOPS_REPOSITORY="${GITOPS_REPOSITORY:-https://github.com/nguyenlpn2015/NovaShop-GitOps.git}"
readonly BACKEND_IMAGE="${BACKEND_IMAGE:-nguyenlpn2015/novashop-backend}"
readonly FRONTEND_IMAGE="${FRONTEND_IMAGE:-nguyenlpn2015/novashop-frontend}"
readonly VERIFY_IMAGE_AVAILABILITY="${VERIFY_IMAGE_AVAILABILITY:-true}"
readonly REGISTRY_TIMEOUT="${REGISTRY_TIMEOUT:-20}"
readonly ENVIRONMENTS=(development staging production)

APP_DIR="${REPO_ROOT}"
GITOPS_DIR=""
APP_DEFAULT_REF=""
TEMPORARY_DIRECTORY=""

PASS_COUNT=0
FAIL_COUNT=0

log() {
  printf '[validate-revisions] %s\n' "$*"
}

die() {
  printf '[validate-revisions] ERROR: %s\n' "$*" >&2
  exit 1
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[validate-revisions] PASS: %s\n' "$1"
}

fail() {
  local label="$1"
  local detail="${2:-}"

  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[validate-revisions] FAIL: %s\n' "${label}" >&2
  if [[ -n "${detail}" ]]; then
    printf '[validate-revisions]       %s\n' "${detail}" >&2
  fi
}

warn() {
  printf '[validate-revisions] WARN: %s\n' "$1" >&2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

remove_temporary_directory() {
  if [[ -n "${TEMPORARY_DIRECTORY}" && -d "${TEMPORARY_DIRECTORY}" ]]; then
    rm -rf -- "${TEMPORARY_DIRECTORY}"
  fi
}

trap remove_temporary_directory EXIT

usage() {
  cat <<'EOF'
Usage: validate-gitops-revisions.sh --gitops-dir DIR [--app-dir DIR]

  --gitops-dir DIR   Path to a NovaShop-GitOps checkout.
  --app-dir DIR      Path to a NovaShop checkout (default: this repository).

Environment:
  APP_DEFAULT_REF             Git ref treated as authoritative (default: auto).
  VERIFY_IMAGE_AVAILABILITY   Query GHCR for each image tag (default: true).
EOF
}

# Emits "repoURL<TAB>targetRevision<TAB>file:line" for every Argo CD source.
#
# Argo CD source blocks always declare repoURL before targetRevision, so the
# most recently seen repoURL owns the next targetRevision. A targetRevision
# without a preceding repoURL is reported as UNKNOWN and fails closed.
write_revision_extractor() {
  cat >"${TEMPORARY_DIRECTORY}/revisions.awk" <<'EOF'
FNR == 1 { repository = "" }
/^[[:space:]]*#/ { next }
match($0, /^[[:space:]]*-?[[:space:]]*repoURL:[[:space:]]*/) {
  value = substr($0, RSTART + RLENGTH)
  gsub(/[[:space:]]+$/, "", value)
  gsub(/["\047]/, "", value)
  repository = value
  next
}
match($0, /^[[:space:]]*targetRevision:[[:space:]]*/) {
  value = substr($0, RSTART + RLENGTH)
  gsub(/[[:space:]]+$/, "", value)
  gsub(/["\047]/, "", value)
  printf "%s\t%s\t%s:%d\n", (repository == "" ? "UNKNOWN" : repository), \
    value, FILENAME, FNR
}
EOF
}

# Emits "section<TAB>tag<TAB>file:line" for backend and frontend image tags.
write_image_tag_extractor() {
  cat >"${TEMPORARY_DIRECTORY}/tags.awk" <<'EOF'
FNR == 1 { section = "" }
/^[[:space:]]*#/ { next }
/^[A-Za-z][A-Za-z0-9_-]*:/ {
  section = $1
  sub(/:$/, "", section)
  next
}
match($0, /^[[:space:]]+tag:[[:space:]]*/) {
  value = substr($0, RSTART + RLENGTH)
  gsub(/[[:space:]]+$/, "", value)
  gsub(/["\047]/, "", value)
  printf "%s\t%s\t%s:%d\n", section, value, FILENAME, FNR
}
EOF
}

resolve_app_default_ref() {
  local candidate

  if [[ -n "${APP_DEFAULT_REF}" ]]; then
    git -C "${APP_DIR}" rev-parse --verify --quiet "${APP_DEFAULT_REF}^{commit}" \
      >/dev/null \
      || die "APP_DEFAULT_REF is not resolvable in ${APP_DIR}: ${APP_DEFAULT_REF}"
    return
  fi

  for candidate in origin/main main; do
    if git -C "${APP_DIR}" rev-parse --verify --quiet "${candidate}^{commit}" \
      >/dev/null; then
      APP_DEFAULT_REF="${candidate}"
      return
    fi
  done

  die "Unable to resolve the NovaShop default branch in ${APP_DIR}."
}

revision_is_immutable_sha() {
  [[ "$1" =~ ^[0-9a-f]{40}$ ]]
}

revision_exists() {
  git -C "${APP_DIR}" cat-file -e "$1^{commit}" 2>/dev/null
}

revision_is_on_default_branch() {
  git -C "${APP_DIR}" merge-base --is-ancestor "$1" "${APP_DEFAULT_REF}" \
    2>/dev/null
}

# Public GHCR packages issue anonymous pull tokens, so tag existence is
# verifiable without credentials. An authorization failure means the package is
# private and cannot be checked here; a 404 means the tag is genuinely absent.
image_tag_exists() {
  local repository="$1"
  local tag="$2"
  local token
  local status

  token="$(
    curl --disable --silent --show-error --fail \
      --max-time "${REGISTRY_TIMEOUT}" \
      "https://ghcr.io/token?service=ghcr.io&scope=repository:${repository}:pull" \
      | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
  )" || return 2
  [[ -n "${token}" ]] || return 2

  status="$(
    curl --disable --silent --show-error \
      --max-time "${REGISTRY_TIMEOUT}" \
      --output /dev/null \
      --write-out '%{http_code}' \
      --header "Authorization: Bearer ${token}" \
      --header 'Accept: application/vnd.oci.image.index.v1+json' \
      --header 'Accept: application/vnd.oci.image.manifest.v1+json' \
      --header 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
      --header 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
      "https://ghcr.io/v2/${repository}/manifests/${tag}"
  )" || return 2

  case "${status}" in
    200) return 0 ;;
    401 | 403) return 2 ;;
    *) return 1 ;;
  esac
}

validate_application_revisions() {
  local records
  local repository
  local revision
  local location
  local app_pin_count=0

  records="$(
    find "${GITOPS_DIR}" \
      -path "${GITOPS_DIR}/.git" -prune -o \
      -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 \
      | xargs -0 --no-run-if-empty \
          awk -f "${TEMPORARY_DIRECTORY}/revisions.awk"
  )"

  if [[ -z "${records}" ]]; then
    fail "GitOps repository declares at least one Argo CD source revision" \
      "No targetRevision was found under ${GITOPS_DIR}."
    return
  fi

  while IFS=$'\t' read -r repository revision location; do
    [[ -n "${repository}" ]] || continue

    if [[ "${repository}" == "UNKNOWN" ]]; then
      fail "targetRevision has an owning repoURL (${location})" \
        "targetRevision ${revision} has no preceding repoURL."
      continue
    fi

    if [[ "${repository}" != "${APP_REPOSITORY}" ]]; then
      continue
    fi

    app_pin_count=$((app_pin_count + 1))

    if ! revision_is_immutable_sha "${revision}"; then
      fail "NovaShop pin is a 40-character commit SHA (${location})" \
        "Found '${revision}'. Branches and tags are mutable and are not permitted."
      continue
    fi

    if ! revision_exists "${revision}"; then
      fail "NovaShop pin exists in the application repository (${location})" \
        "Commit ${revision} was not found. Fetch full history before validating."
      continue
    fi

    if ! revision_is_on_default_branch "${revision}"; then
      fail "NovaShop pin is reachable from ${APP_DEFAULT_REF} (${location})" \
        "Commit ${revision} lives only outside the default branch; deleting that branch would break rendering and recovery."
      continue
    fi

    pass "NovaShop pin ${revision:0:12} is durable (${location})"
  done <<<"${records}"

  if (( app_pin_count == 0 )); then
    fail "GitOps repository pins the NovaShop repository at least once" \
      "No source referenced ${APP_REPOSITORY}; the extractor may be stale."
  fi
}

validate_gitops_self_references() {
  local records
  local repository
  local revision
  local location

  records="$(
    find "${GITOPS_DIR}" \
      -path "${GITOPS_DIR}/.git" -prune -o \
      -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 \
      | xargs -0 --no-run-if-empty \
          awk -f "${TEMPORARY_DIRECTORY}/revisions.awk"
  )"

  while IFS=$'\t' read -r repository revision location; do
    [[ "${repository}" == "${GITOPS_REPOSITORY}" ]] || continue

    # The desired-state repository is the reconciliation root and intentionally
    # tracks its own default branch.
    if [[ "${revision}" == "main" ]]; then
      pass "GitOps self-reference tracks main (${location})"
    else
      fail "GitOps self-reference tracks main (${location})" \
        "Found '${revision}'. A pinned self-reference stops Argo CD from observing merged changes."
    fi
  done <<<"${records}"
}

validate_bootstrap_revisions() {
  local records
  local repository
  local revision
  local location
  local manifest

  for manifest in "${APP_DIR}"/argocd/application*.yaml; do
    [[ -f "${manifest}" ]] || continue

    records="$(awk -f "${TEMPORARY_DIRECTORY}/revisions.awk" "${manifest}")"
    while IFS=$'\t' read -r repository revision location; do
      [[ -n "${repository}" ]] || continue

      if [[ "${repository}" != "${GITOPS_REPOSITORY}" ]]; then
        fail "Bootstrap root Application targets the GitOps repository (${location})" \
          "Found '${repository}'. Bootstrap must not deploy application resources from the application repository."
        continue
      fi

      if [[ "${revision}" == "main" ]]; then
        pass "Bootstrap root Application tracks GitOps main (${location})"
      else
        fail "Bootstrap root Application tracks GitOps main (${location})" \
          "Found '${revision}'. A pinned bootstrap root cannot receive reviewed GitOps changes."
      fi
    done <<<"${records}"
  done
}

validate_image_tags() {
  local environment
  local values_file
  local records
  local section
  local tag
  local location
  local backend_tag
  local frontend_tag
  local availability_status

  for environment in "${ENVIRONMENTS[@]}"; do
    values_file="${GITOPS_DIR}/apps/novashop/values/${environment}.yaml"

    if [[ ! -f "${values_file}" ]]; then
      fail "Environment values file exists: ${environment}" \
        "Missing ${values_file}."
      continue
    fi

    backend_tag=""
    frontend_tag=""
    records="$(awk -f "${TEMPORARY_DIRECTORY}/tags.awk" "${values_file}")"

    while IFS=$'\t' read -r section tag location; do
      case "${section}" in
        backend) backend_tag="${tag}" ;;
        frontend) frontend_tag="${tag}" ;;
        *) continue ;;
      esac

      if [[ "${tag}" == "latest" ]]; then
        fail "${environment} ${section} image tag is immutable (${location})" \
          "The mutable 'latest' tag must never appear in desired state."
        continue
      fi

      if ! revision_is_immutable_sha "${tag}"; then
        fail "${environment} ${section} image tag is a commit SHA (${location})" \
          "Found '${tag}'."
        continue
      fi

      if ! revision_exists "${tag}"; then
        fail "${environment} ${section} image tag maps to a known commit (${location})" \
          "Commit ${tag} was not found in ${APP_DIR}."
        continue
      fi

      if ! revision_is_on_default_branch "${tag}"; then
        fail "${environment} ${section} image tag is built from ${APP_DEFAULT_REF} (${location})" \
          "Commit ${tag} is not reachable from the default branch."
        continue
      fi

      pass "${environment} ${section} image tag ${tag:0:12} is traceable"
    done <<<"${records}"

    if [[ -n "${backend_tag}" && -n "${frontend_tag}" ]]; then
      if [[ "${backend_tag}" == "${frontend_tag}" ]]; then
        pass "${environment} deploys backend and frontend from one source commit"
      else
        fail "${environment} deploys backend and frontend from one source commit" \
          "backend=${backend_tag} frontend=${frontend_tag}. Split revisions defeat promotion traceability."
      fi
    else
      fail "${environment} declares both image tags" \
        "backend='${backend_tag}' frontend='${frontend_tag}'."
    fi

    if [[ "${VERIFY_IMAGE_AVAILABILITY}" != "true" ]]; then
      continue
    fi

    for section in backend frontend; do
      if [[ "${section}" == "backend" ]]; then
        tag="${backend_tag}"
        location="${BACKEND_IMAGE}"
      else
        tag="${frontend_tag}"
        location="${FRONTEND_IMAGE}"
      fi
      [[ -n "${tag}" ]] || continue

      availability_status=0
      image_tag_exists "${location}" "${tag}" || availability_status=$?
      case "${availability_status}" in
        0)
          pass "${location}:${tag:0:12} is published"
          ;;
        1)
          fail "${location}:${tag:0:12} is published" \
            "The registry has no manifest for this tag; the deployment would fail with ImagePullBackOff."
          ;;
        *)
          warn "Could not verify ${location}:${tag:0:12}; the package is private or the registry was unreachable."
          ;;
      esac
    done
  done
}

main() {
  while (( $# > 0 )); do
    case "$1" in
      --gitops-dir)
        [[ $# -ge 2 ]] || die 'Option --gitops-dir requires a value.'
        GITOPS_DIR="$2"
        shift
        ;;
      --app-dir)
        [[ $# -ge 2 ]] || die 'Option --app-dir requires a value.'
        APP_DIR="$2"
        shift
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
  require_command curl
  require_command find
  require_command git
  require_command sed
  require_command xargs

  [[ -n "${GITOPS_DIR}" ]] || { usage >&2; die 'Option --gitops-dir is required.'; }
  [[ -d "${GITOPS_DIR}" ]] || die "GitOps directory does not exist: ${GITOPS_DIR}"
  [[ -d "${APP_DIR}" ]] || die "Application directory does not exist: ${APP_DIR}"

  GITOPS_DIR="$(cd -- "${GITOPS_DIR}" && pwd)"
  APP_DIR="$(cd -- "${APP_DIR}" && pwd)"

  git -C "${APP_DIR}" rev-parse --git-dir >/dev/null 2>&1 \
    || die "Not a readable Git repository: ${APP_DIR}. If Git reports dubious ownership, run: git config --global --add safe.directory ${APP_DIR}"

  TEMPORARY_DIRECTORY="$(mktemp -d)"
  write_revision_extractor
  write_image_tag_extractor
  resolve_app_default_ref

  log "Application repository: ${APP_DIR} (authoritative ref: ${APP_DEFAULT_REF})"
  log "GitOps repository: ${GITOPS_DIR}"

  validate_application_revisions
  validate_gitops_self_references
  validate_bootstrap_revisions
  validate_image_tags

  if (( FAIL_COUNT > 0 )); then
    printf '[validate-revisions] RESULT: FAIL (%d passed, %d failed)\n' \
      "${PASS_COUNT}" "${FAIL_COUNT}" >&2
    exit 1
  fi

  printf '[validate-revisions] RESULT: PASS (%d passed, 0 failed)\n' \
    "${PASS_COUNT}"
}

main "$@"
