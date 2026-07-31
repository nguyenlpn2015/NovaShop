#!/usr/bin/env bash

# Platform validation gate.
#
# Every deployment-affecting change in NovaShop or NovaShop-GitOps must pass
# this script before it can be merged, and the release workflow must pass it
# before any container image is published. It renders the desired state exactly
# the way Argo CD does — the pinned Helm chart plus the environment values plus
# the deployment-target overlay — and then validates the result against the
# Kubernetes and CRD schemas.
#
# The script is the single source of truth for platform validation and is
# invoked identically from a developer workstation, from NovaShop CI, and from
# the NovaShop-GitOps pull request workflow.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT
readonly KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.33.0}"

# The catalog URL is held in its own variable because a literal '}' inside a
# ${parameter:-default} expansion terminates the expansion early and silently
# truncates the Go template placeholders.
CRD_SCHEMA_CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
readonly CRD_SCHEMA_CATALOG
readonly CRD_SCHEMA_LOCATION="${CRD_SCHEMA_LOCATION-${CRD_SCHEMA_CATALOG}}"
readonly ENVIRONMENTS=(development staging production)
readonly DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-ubuntu-k3s}"

# Each GitOps phase must source its edge manifests from exactly one directory.
# The mapping is asserted so that a JSON patch addressing a source by index can
# never silently rewrite the Helm chart source instead of the edge source.
declare -Ar PHASE_EDGE_PATHS=(
  [http]="kubernetes/ingress/http"
  [tls-baseline]="kubernetes/ingress/baseline"
  [tls-enforced]="kubernetes/ingress/examples"
  [tls]="kubernetes/ingress/examples"
)

APP_DIR="${REPO_ROOT}"
GITOPS_DIR=""
SCOPE="all"
SKIP_LINT=false
SKIP_SCHEMA_VALIDATION="${SKIP_SCHEMA_VALIDATION:-false}"
KUSTOMIZE=()
TEMPORARY_DIRECTORY=""

PASS_COUNT=0
FAIL_COUNT=0

log() {
  printf '[validate-platform] %s\n' "$*"
}

die() {
  printf '[validate-platform] ERROR: %s\n' "$*" >&2
  exit 1
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[validate-platform] PASS: %s\n' "$1"
}

fail() {
  local label="$1"
  local detail="${2:-}"

  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[validate-platform] FAIL: %s\n' "${label}" >&2
  if [[ -n "${detail}" ]]; then
    printf '%s\n' "${detail}" | sed 's/^/[validate-platform]       /' >&2
  fi
}

run_check() {
  local label="$1"
  local output

  shift
  if output="$("$@" 2>&1)"; then
    pass "${label}"
  else
    fail "${label}" "${output}"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 \
    || die "Required command not found: $1. See docs/PLATFORM_GUARDRAILS.md for the toolchain."
}

remove_temporary_directory() {
  if [[ -n "${TEMPORARY_DIRECTORY}" && -d "${TEMPORARY_DIRECTORY}" ]]; then
    rm -rf -- "${TEMPORARY_DIRECTORY}"
  fi
}

trap remove_temporary_directory EXIT

usage() {
  cat <<'EOF'
Usage: validate-platform.sh [options]

  --gitops-dir DIR   Path to a NovaShop-GitOps checkout. Required unless the
                     scope is 'application'.
  --app-dir DIR      Path to a NovaShop checkout (default: this repository).
  --scope SCOPE      all | application | platform (default: all).
                       application  Lint and schema-validate this repository.
                       platform     Cross-repository render and revision gate.
  --skip-lint        Skip yamllint.

Environment:
  KUBERNETES_VERSION        Schema target version (default: 1.33.0).
  SKIP_SCHEMA_VALIDATION    Set to true when the CRD catalog is unreachable.
EOF
}

resolve_kustomize() {
  if command -v kustomize >/dev/null 2>&1; then
    KUSTOMIZE=(kustomize build)
    return
  fi

  # kubectl embeds Kustomize, which keeps the required toolchain smaller.
  if command -v kubectl >/dev/null 2>&1; then
    KUSTOMIZE=(kubectl kustomize)
    return
  fi

  die 'Neither kustomize nor kubectl is available.'
}

# Only tracked files are linted. Enumerating through Git excludes vendored
# directories such as frontend/node_modules deterministically on every
# platform, which path-glob ignores cannot do once Windows separators appear.
collect_lint_targets() {
  local directory="$1"

  if git -C "${directory}" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "${directory}" ls-files -- '*.yaml' '*.yml' \
      | grep -v '^helm/novashop/templates/' \
      | sed "s|^|${directory}/|"
    return
  fi

  find "${directory}" \
    -path "${directory}/.git" -prune -o \
    -path '*/node_modules' -prune -o \
    -path "${directory}/helm/novashop/templates" -prune -o \
    -type f \( -name '*.yaml' -o -name '*.yml' \) -print \
    | sort
}

lint_yaml() {
  local target
  local file
  local -a files

  for target in "$@"; do
    [[ -n "${target}" && -d "${target}" ]] || continue

    files=()
    while IFS= read -r file; do
      [[ -n "${file}" ]] && files+=("${file}")
    done < <(collect_lint_targets "${target}")

    if (( ${#files[@]} == 0 )); then
      fail "yamllint has files to inspect: ${target}" \
        'No tracked YAML document was found.'
      continue
    fi

    run_check "yamllint is clean: ${target} (${#files[@]} files)" \
      yamllint --strict --config-file "${APP_DIR}/.yamllint.yaml" "${files[@]}"
  done
}

discover_phases() {
  local phase_root="${GITOPS_DIR}/clusters/${DEPLOYMENT_TARGET}/phases"
  local phase_directory

  [[ -d "${phase_root}" ]] || return 0

  for phase_directory in "${phase_root}"/*/; do
    [[ -f "${phase_directory}kustomization.yaml" ]] || continue
    basename -- "${phase_directory%/}"
  done
}

build_overlay() {
  local overlay_path="$1"
  local output_file="$2"

  "${KUSTOMIZE[@]}" "${overlay_path}" >"${output_file}"
}

# Isolates the ApplicationSet document from a multi-document render so that
# source assertions cannot be satisfied or broken by a sibling Application.
extract_applicationset_document() {
  awk '
    function flush() {
      if (buffer ~ /(^|\n)kind:[[:space:]]*ApplicationSet[[:space:]]*(\n|$)/) {
        printf "%s", buffer
      }
      buffer = ""
    }
    /^---[[:space:]]*$/ { flush(); next }
    { buffer = buffer $0 "\n" }
    END { flush() }
  ' "$1"
}

# A rendered phase must contain exactly one Helm chart source, one values
# reference, and one edge manifest source at the directory that belongs to the
# phase. Kustomize JSON patches address Argo CD sources positionally, so this
# assertion is what prevents an index drift from silently repointing the chart.
assert_phase_sources() {
  local phase="$1"
  local rendered="$2"
  local expected_edge_path="${PHASE_EDGE_PATHS[${phase}]:-}"
  local application_set="${rendered}.applicationset"
  local chart_sources
  local values_references
  local edge_sources
  local distinct_revisions

  extract_applicationset_document "${rendered}" >"${application_set}"
  if [[ ! -s "${application_set}" ]]; then
    fail "phase ${phase} renders the novashop ApplicationSet" \
      'No document with kind: ApplicationSet was produced.'
    return
  fi

  # Kustomize emits sequence entries with a leading dash on the first key, so
  # every key match must tolerate an optional '- ' prefix.
  chart_sources="$(grep -cE '^[[:space:]]*(-[[:space:]]+)?path:[[:space:]]*helm/novashop[[:space:]]*$' "${application_set}" || true)"
  values_references="$(grep -cE '^[[:space:]]*(-[[:space:]]+)?ref:[[:space:]]*values[[:space:]]*$' "${application_set}" || true)"
  edge_sources="$(grep -cE '^[[:space:]]*(-[[:space:]]+)?path:[[:space:]]*kubernetes/ingress/' "${application_set}" || true)"

  if [[ "${chart_sources}" == "1" ]]; then
    pass "phase ${phase} renders exactly one Helm chart source"
  else
    fail "phase ${phase} renders exactly one Helm chart source" \
      "Found ${chart_sources} occurrences of 'path: helm/novashop'. A positional source patch has drifted."
  fi

  if [[ "${values_references}" == "1" ]]; then
    pass "phase ${phase} renders exactly one values reference"
  else
    fail "phase ${phase} renders exactly one values reference" \
      "Found ${values_references} occurrences of 'ref: values'."
  fi

  if [[ "${edge_sources}" == "1" ]]; then
    pass "phase ${phase} renders exactly one edge manifest source"
  else
    fail "phase ${phase} renders exactly one edge manifest source" \
      "Found ${edge_sources} sources under kubernetes/ingress/."
  fi

  if [[ -n "${expected_edge_path}" ]]; then
    if grep -qE "^[[:space:]]*(-[[:space:]]+)?path:[[:space:]]*${expected_edge_path}[[:space:]]*$" \
      "${application_set}"; then
      pass "phase ${phase} sources edge manifests from ${expected_edge_path}"
    else
      fail "phase ${phase} sources edge manifests from ${expected_edge_path}" \
        "$(grep -nE '^[[:space:]]*(-[[:space:]]+)?path:' "${application_set}" || true)"
    fi
  else
    log "Phase ${phase} has no declared edge path expectation; structural checks only."
  fi

  distinct_revisions="$(
    grep -o 'targetRevision:[[:space:]]*[0-9a-f]\{40\}' "${rendered}" \
      | awk '{ print $2 }' \
      | sort --unique \
      | wc --lines
  )"
  if (( distinct_revisions <= 1 )); then
    pass "phase ${phase} pins a single application revision"
  else
    fail "phase ${phase} pins a single application revision" \
      "Found ${distinct_revisions} distinct pinned revisions; a mixed render deploys inconsistent desired state."
  fi
}

validate_kustomize_overlays() {
  local overlay
  local overlay_path
  local phase
  local rendered
  local -a overlays=(in-cluster "${DEPLOYMENT_TARGET}")

  for overlay in "${overlays[@]}"; do
    overlay_path="${GITOPS_DIR}/clusters/${overlay}"
    [[ -d "${overlay_path}" ]] || {
      fail "cluster overlay exists: ${overlay}" "Missing ${overlay_path}."
      continue
    }

    rendered="${TEMPORARY_DIRECTORY}/cluster-${overlay}.yaml"
    run_check "kustomize build succeeds: clusters/${overlay}" \
      build_overlay "${overlay_path}" "${rendered}"
  done

  while read -r phase; do
    [[ -n "${phase}" ]] || continue
    overlay_path="${GITOPS_DIR}/clusters/${DEPLOYMENT_TARGET}/phases/${phase}"
    rendered="${TEMPORARY_DIRECTORY}/phase-${phase}.yaml"

    if ! build_overlay "${overlay_path}" "${rendered}" 2>"${rendered}.err"; then
      fail "kustomize build succeeds: phases/${phase}" \
        "$(cat "${rendered}.err")"
      continue
    fi
    pass "kustomize build succeeds: phases/${phase}"
    assert_phase_sources "${phase}" "${rendered}"
  done < <(discover_phases)
}

render_helm_environment() {
  local environment="$1"
  local output_file="$2"
  shift 2

  helm template novashop "${APP_DIR}/helm/novashop" \
    --namespace "novashop-${environment}" \
    --kube-version "${KUBERNETES_VERSION}" \
    "$@" \
    >"${output_file}"
}

lint_helm_environment() {
  helm lint "${APP_DIR}/helm/novashop" "$@"
}

# Argo CD renders the base environment values for the in-cluster overlay and
# the base values plus the deployment-target overlay for Ubuntu k3s. Both
# combinations are validated so a target-specific override cannot break only
# one cluster.
validate_helm_renders() {
  local environment
  local base_values
  local target_values
  local -a value_arguments

  for environment in "${ENVIRONMENTS[@]}"; do
    base_values="${GITOPS_DIR}/apps/novashop/values/${environment}.yaml"
    target_values="${GITOPS_DIR}/apps/novashop/targets/${DEPLOYMENT_TARGET}/${environment}.yaml"

    if [[ ! -f "${base_values}" ]]; then
      fail "environment values exist: ${environment}" "Missing ${base_values}."
      continue
    fi

    value_arguments=(--values "${base_values}")
    run_check "helm lint succeeds: ${environment} (in-cluster)" \
      lint_helm_environment "${value_arguments[@]}"
    run_check "helm template succeeds: ${environment} (in-cluster)" \
      render_helm_environment "${environment}" \
        "${TEMPORARY_DIRECTORY}/helm-in-cluster-${environment}.yaml" \
        "${value_arguments[@]}"

    if [[ ! -f "${target_values}" ]]; then
      fail "deployment target values exist: ${DEPLOYMENT_TARGET}/${environment}" \
        "Missing ${target_values}."
      continue
    fi

    value_arguments+=(--values "${target_values}")
    run_check "helm lint succeeds: ${environment} (${DEPLOYMENT_TARGET})" \
      lint_helm_environment "${value_arguments[@]}"
    run_check "helm template succeeds: ${environment} (${DEPLOYMENT_TARGET})" \
      render_helm_environment "${environment}" \
        "${TEMPORARY_DIRECTORY}/helm-${DEPLOYMENT_TARGET}-${environment}.yaml" \
        "${value_arguments[@]}"
  done
}

collect_application_manifests() {
  find "${APP_DIR}/kubernetes" "${APP_DIR}/argocd" \
    -type f -name '*.yaml' \
    ! -name 'helm-values.yaml' \
    -print 2>/dev/null \
    | sort
}

validate_schemas() {
  local -a manifests=()
  local manifest

  if [[ "${SKIP_SCHEMA_VALIDATION}" == "true" ]]; then
    log 'Schema validation skipped by request; the CRD catalog was not consulted.'
    return
  fi

  while IFS= read -r manifest; do
    [[ -n "${manifest}" ]] && manifests+=("${manifest}")
  done < <(collect_application_manifests)

  while IFS= read -r manifest; do
    [[ -n "${manifest}" ]] && manifests+=("${manifest}")
  done < <(find "${TEMPORARY_DIRECTORY}" -maxdepth 1 -type f -name '*.yaml' -print | sort)

  (( ${#manifests[@]} > 0 )) \
    || { fail 'schema validation has manifests to inspect' 'No manifest was collected.'; return; }

  run_check "kubeconform accepts every rendered and static manifest (${#manifests[@]} files)" \
    kubeconform \
      -strict \
      -summary \
      -kubernetes-version "${KUBERNETES_VERSION}" \
      -schema-location default \
      -schema-location "${CRD_SCHEMA_LOCATION}" \
      "${manifests[@]}"
}

validate_revisions() {
  run_check 'cross-repository revisions are durable and traceable' \
    bash "${SCRIPT_DIR}/validate-gitops-revisions.sh" \
      --gitops-dir "${GITOPS_DIR}" \
      --app-dir "${APP_DIR}"
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
      --scope)
        [[ $# -ge 2 ]] || die 'Option --scope requires a value.'
        SCOPE="$2"
        shift
        ;;
      --skip-lint)
        SKIP_LINT=true
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

  case "${SCOPE}" in
    all | application | platform) ;;
    *) die "Unsupported scope: ${SCOPE}" ;;
  esac

  require_command awk
  require_command find
  require_command grep
  require_command sed
  require_command sort
  [[ "${SKIP_LINT}" == "true" ]] || require_command yamllint
  [[ "${SKIP_SCHEMA_VALIDATION}" == "true" ]] || require_command kubeconform

  APP_DIR="$(cd -- "${APP_DIR}" && pwd)"
  [[ -f "${APP_DIR}/.yamllint.yaml" ]] \
    || die "Lint policy not found: ${APP_DIR}/.yamllint.yaml"

  if [[ "${SCOPE}" != "application" ]]; then
    [[ -n "${GITOPS_DIR}" ]] \
      || { usage >&2; die "Scope '${SCOPE}' requires --gitops-dir."; }
    [[ -d "${GITOPS_DIR}" ]] || die "GitOps directory does not exist: ${GITOPS_DIR}"
    GITOPS_DIR="$(cd -- "${GITOPS_DIR}" && pwd)"
    require_command helm
    resolve_kustomize
  fi

  TEMPORARY_DIRECTORY="$(mktemp -d)"

  log "Scope: ${SCOPE}"
  log "Application repository: ${APP_DIR}"
  [[ -z "${GITOPS_DIR}" ]] || log "GitOps repository: ${GITOPS_DIR}"

  if [[ "${SKIP_LINT}" != "true" ]]; then
    lint_yaml "${APP_DIR}" "${GITOPS_DIR}"
  fi

  if [[ "${SCOPE}" != "application" ]]; then
    validate_revisions
    validate_kustomize_overlays
    validate_helm_renders
  fi

  validate_schemas

  if (( FAIL_COUNT > 0 )); then
    printf '[validate-platform] RESULT: FAIL (%d passed, %d failed)\n' \
      "${PASS_COUNT}" "${FAIL_COUNT}" >&2
    exit 1
  fi

  printf '[validate-platform] RESULT: PASS (%d passed, 0 failed)\n' \
    "${PASS_COUNT}"
}

main "$@"
