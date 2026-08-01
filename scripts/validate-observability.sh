#!/usr/bin/env bash

# Validates the observability desired state before it can be merged.
#
# A monitoring stack fails in a way ordinary validation does not catch: a scrape
# job whose relabel rules match nothing renders correctly, schema-validates
# correctly, deploys correctly, and collects nothing. The failure looks exactly
# like a healthy system with no problems to report, which is the most dangerous
# state an observability platform can be in.
#
# This script therefore checks two things that rendering alone cannot:
#
#   1. The generated Prometheus configuration parses under promtool, the same
#      binary the server uses.
#   2. Every scrape job this platform depends on is actually present in the
#      generated configuration, by name.
#
# Target liveness is asserted separately, after deployment, by
# scripts/linux/verify.sh.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT
readonly PROMETHEUS_CHART_VERSION="${PROMETHEUS_CHART_VERSION:-29.20.1}"
readonly GRAFANA_CHART_VERSION="${GRAFANA_CHART_VERSION:-10.5.15}"
readonly POSTGRES_EXPORTER_CHART_VERSION="${POSTGRES_EXPORTER_CHART_VERSION:-8.2.0}"
readonly REDIS_EXPORTER_CHART_VERSION="${REDIS_EXPORTER_CHART_VERSION:-6.28.0}"
readonly LOKI_CHART_VERSION="${LOKI_CHART_VERSION:-7.2.0}"
readonly ALLOY_CHART_VERSION="${ALLOY_CHART_VERSION:-1.11.0}"
readonly PROMETHEUS_IMAGE="${PROMETHEUS_IMAGE:-prom/prometheus:v3.13.2}"
readonly OBSERVABILITY_DIR="${REPO_ROOT}/kubernetes/observability"
readonly NAMESPACE="${OBSERVABILITY_NAMESPACE:-observability}"
readonly DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-ubuntu-k3s}"
GITOPS_DIR="${GITOPS_DIR:-}"

# Every job the platform depends on. A job silently disappearing from the
# rendered configuration is the regression this list exists to catch.
readonly REQUIRED_JOBS=(
  argocd
  cert-manager
  traefik
  kubernetes-api-servers
  kubernetes-nodes
  kubernetes-nodes-cadvisor
  kubernetes-service-endpoints
  kubernetes-pods
  prometheus
)

TEMPORARY_DIRECTORY=""
PYTHON=""
PASS_COUNT=0
FAIL_COUNT=0

log() {
  printf '[validate-observability] %s\n' "$*"
}

die() {
  printf '[validate-observability] ERROR: %s\n' "$*" >&2
  exit 1
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[validate-observability] PASS: %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[validate-observability] FAIL: %s\n' "$1" >&2
  if [[ -n "${2:-}" ]]; then
    printf '%s\n' "$2" | sed 's/^/[validate-observability]       /' >&2
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# `python3` on Windows commonly resolves to the Microsoft Store launcher, which
# is on PATH but is not an interpreter. Each candidate is executed rather than
# merely located.
resolve_python() {
  local candidate

  for candidate in python3 python py; do
    if command -v "${candidate}" >/dev/null 2>&1 \
      && "${candidate}" -c 'import yaml' >/dev/null 2>&1; then
      PYTHON="${candidate}"
      return
    fi
  done

  die 'No Python interpreter with PyYAML was found. Install one, or pip install pyyaml.'
}

# Git Bash rewrites POSIX-looking arguments into Windows paths before a native
# binary sees them, which corrupts both the bind mount source and the in
# container path. Conversion is done deliberately, and the rewriting is disabled
# for the call itself. Both are no-ops on Linux.
host_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath --windows "$1"
  else
    printf '%s' "$1"
  fi
}

docker_run() {
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"
}

remove_temporary_directory() {
  if [[ -n "${TEMPORARY_DIRECTORY}" && -d "${TEMPORARY_DIRECTORY}" ]]; then
    rm -rf -- "${TEMPORARY_DIRECTORY}"
  fi
}

trap remove_temporary_directory EXIT

render_charts() {
  helm repo add prometheus-community \
    https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true

  if helm template novashop-prometheus prometheus-community/prometheus \
    --version "${PROMETHEUS_CHART_VERSION}" \
    --namespace "${NAMESPACE}" \
    --values "${OBSERVABILITY_DIR}/prometheus/helm-values.yaml" \
    >"${TEMPORARY_DIRECTORY}/prometheus.yaml" 2>"${TEMPORARY_DIRECTORY}/prometheus.err"; then
    pass "prometheus chart ${PROMETHEUS_CHART_VERSION} renders"
  else
    fail "prometheus chart ${PROMETHEUS_CHART_VERSION} renders" \
      "$(cat "${TEMPORARY_DIRECTORY}/prometheus.err")"
    return 1
  fi

  if helm template novashop-grafana grafana/grafana \
    --version "${GRAFANA_CHART_VERSION}" \
    --namespace "${NAMESPACE}" \
    --values "${OBSERVABILITY_DIR}/grafana/helm-values.yaml" \
    >"${TEMPORARY_DIRECTORY}/grafana.yaml" 2>"${TEMPORARY_DIRECTORY}/grafana.err"; then
    pass "grafana chart ${GRAFANA_CHART_VERSION} renders"
  else
    fail "grafana chart ${GRAFANA_CHART_VERSION} renders" \
      "$(cat "${TEMPORARY_DIRECTORY}/grafana.err")"
  fi

  render_exporter postgres "${POSTGRES_EXPORTER_CHART_VERSION}"
  render_exporter redis "${REDIS_EXPORTER_CHART_VERSION}"
  render_grafana_chart loki "${LOKI_CHART_VERSION}"
  render_grafana_chart alloy "${ALLOY_CHART_VERSION}"
}

render_grafana_chart() {
  local name="$1"
  local version="$2"
  local values="${OBSERVABILITY_DIR}/${name}/helm-values.yaml"

  [[ -f "${values}" ]] || { fail "${name} values exist" "Missing ${values}."; return; }

  if helm template "novashop-${name}" "grafana/${name}" \
    --version "${version}" \
    --namespace "${NAMESPACE}" \
    --values "${values}" \
    >"${TEMPORARY_DIRECTORY}/${name}.yaml" \
    2>"${TEMPORARY_DIRECTORY}/${name}.err"; then
    pass "${name} chart ${version} renders"
  else
    fail "${name} chart ${version} renders" \
      "$(cat "${TEMPORARY_DIRECTORY}/${name}.err")"
  fi
}

# The Loki chart defaults to a scalable deployment with two memcached caches
# whose default memory requests alone exceed what this node has free, plus a
# gateway, a canary, and a MinIO instance. Each is disabled deliberately, and a
# chart upgrade that quietly reintroduces one would exhaust the node.
check_loki_is_single_binary() {
  local rendered="${TEMPORARY_DIRECTORY}/loki.yaml"
  local unwanted

  [[ -s "${rendered}" ]] || return 0

  unwanted="$(
    grep -hoE 'novashop-loki-(chunks-cache|results-cache|gateway|canary|minio)[a-z-]*' \
      "${rendered}" | sort -u || true
  )"

  if [[ -z "${unwanted}" ]]; then
    pass 'loki renders without caches, gateway, canary, or minio'
  else
    fail 'loki renders without caches, gateway, canary, or minio' "${unwanted}"
  fi

  # Without compactor retention Loki never deletes, and the volume fills
  # silently on a node that also hosts the database.
  if grep -qE 'retention_enabled:[[:space:]]*true' "${rendered}"; then
    pass 'loki compactor retention is enabled'
  else
    fail 'loki compactor retention is enabled' \
      'The volume would fill and never be reclaimed.'
  fi
}

render_exporter() {
  local name="$1"
  local version="$2"
  local values="${OBSERVABILITY_DIR}/${name}-exporter/helm-values.yaml"

  [[ -f "${values}" ]] || { fail "${name}-exporter values exist" "Missing ${values}."; return; }

  if helm template "novashop-${name}-exporter" \
    "prometheus-community/prometheus-${name}-exporter" \
    --version "${version}" \
    --namespace "${NAMESPACE}" \
    --values "${values}" \
    >"${TEMPORARY_DIRECTORY}/${name}-exporter.yaml" \
    2>"${TEMPORARY_DIRECTORY}/${name}-exporter.err"; then
    pass "${name}-exporter chart ${version} renders"
  else
    fail "${name}-exporter chart ${version} renders" \
      "$(cat "${TEMPORARY_DIRECTORY}/${name}-exporter.err")"
  fi
}

# The exporters are collected by annotation discovery rather than by a dedicated
# scrape job. A Service that loses the annotation keeps running and keeps
# serving metrics that nobody reads, which is indistinguishable from a datastore
# with nothing to report.
check_exporters_are_discoverable() {
  local name
  local rendered
  local scrape

  for name in postgres redis; do
    rendered="${TEMPORARY_DIRECTORY}/${name}-exporter.yaml"
    [[ -s "${rendered}" ]] || continue

    scrape="$(
      "${PYTHON}" - "${rendered}" <<'PY'
import sys, yaml
for document in yaml.safe_load_all(open(sys.argv[1], encoding="utf-8")):
    if not document or document.get("kind") != "Service":
        continue
    annotations = document["metadata"].get("annotations") or {}
    print(annotations.get("prometheus.io/scrape", ""))
    break
PY
    )"

    if [[ "${scrape}" == "true" ]]; then
      pass "${name}-exporter Service is annotated for scraping"
    else
      fail "${name}-exporter Service is annotated for scraping" \
        "prometheus.io/scrape is '${scrape:-unset}'. The exporter would run and be collected by nothing."
    fi
  done
}

extract_prometheus_config() {
  "${PYTHON}" - "${TEMPORARY_DIRECTORY}/prometheus.yaml" \
    "${TEMPORARY_DIRECTORY}/config" <<'PY'
import os, sys, yaml

source, destination = sys.argv[1], sys.argv[2]
os.makedirs(destination, exist_ok=True)
written = []
for document in yaml.safe_load_all(open(source, encoding="utf-8")):
    if not document or document.get("kind") != "ConfigMap":
        continue
    for name, body in (document.get("data") or {}).items():
        if name.endswith((".yml", ".yaml")):
            with open(os.path.join(destination, name), "w",
                      encoding="utf-8", newline="\n") as handle:
                handle.write(body)
            written.append(name)

# The chart references two legacy rule paths that it mounts as empty files.
for name in ("rules", "alerts"):
    open(os.path.join(destination, name), "a", encoding="utf-8").close()

sys.exit(0 if "prometheus.yml" in written else 1)
PY
}

check_prometheus_config() {
  local token_directory="${TEMPORARY_DIRECTORY}/serviceaccount"
  local output

  if ! extract_prometheus_config; then
    fail 'rendered output contains a prometheus.yml ConfigMap'
    return 1
  fi

  # promtool resolves the in-cluster bearer token path while checking Kubernetes
  # service discovery, so a placeholder stands in for it outside the cluster.
  mkdir -p "${token_directory}"
  printf 'placeholder\n' >"${token_directory}/token"

  if output="$(
    docker_run run --rm --entrypoint promtool \
      --volume "$(host_path "${TEMPORARY_DIRECTORY}/config"):/etc/config:ro" \
      --volume "$(host_path "${token_directory}"):/var/run/secrets/kubernetes.io/serviceaccount:ro" \
      "${PROMETHEUS_IMAGE}" check config /etc/config/prometheus.yml 2>&1
  )"; then
    pass 'promtool accepts the generated Prometheus configuration'
  else
    fail 'promtool accepts the generated Prometheus configuration' "${output}"
  fi
}

check_required_jobs() {
  local configuration="${TEMPORARY_DIRECTORY}/config/prometheus.yml"
  local job

  [[ -r "${configuration}" ]] || { fail 'generated configuration is readable'; return; }

  for job in "${REQUIRED_JOBS[@]}"; do
    if grep -qE "^[[:space:]]*-?[[:space:]]*job_name:[[:space:]]*${job}[[:space:]]*$" \
      "${configuration}"; then
      pass "scrape job is present: ${job}"
    else
      fail "scrape job is present: ${job}" \
        'A dependency of this platform would be collected by nothing.'
    fi
  done
}

# Traefik publishes metrics on the pod only; its Service exposes web and
# websecure and nothing else. An endpoints-based job would render, validate, and
# quietly collect zero series, so the discovery role is asserted explicitly.
check_traefik_uses_pod_discovery() {
  local configuration="${TEMPORARY_DIRECTORY}/config/prometheus.yml"
  local role

  role="$(
    "${PYTHON}" - "${configuration}" <<'PY'
import sys, yaml
config = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
for job in config.get("scrape_configs", []):
    if job.get("job_name") == "traefik":
        roles = {
            discovery.get("role")
            for discovery in job.get("kubernetes_sd_configs", [])
        }
        print(",".join(sorted(filter(None, roles))))
        break
PY
  )"

  if [[ "${role}" == "pod" ]]; then
    pass 'traefik is discovered by pod, not by endpoints'
  else
    fail 'traefik is discovered by pod, not by endpoints' \
      "Discovery role is '${role:-none}'. The Traefik Service does not expose the metrics port, so any other role collects nothing."
  fi
}

# Argo CD refuses any resource kind absent from its AppProject whitelist, and it
# refuses it at sync time — after review, after merge, with the Application
# reporting Missing and no clue in the pull request. Loki failed exactly this
# way: DaemonSet and PersistentVolumeClaim were whitelisted for the exporters,
# StatefulSet was not, and the Loki single binary is a StatefulSet.
check_kinds_are_permitted() {
  local project="${GITOPS_DIR}/clusters/${DEPLOYMENT_TARGET}/phases/tls-baseline/platform-project.yaml"
  local missing

  if [[ -z "${GITOPS_DIR}" || ! -f "${project}" ]]; then
    log 'AppProject not available; skipping kind permission check.'
    return
  fi

  missing="$(
    "${PYTHON}" - "${project}" "${TEMPORARY_DIRECTORY}" <<'PY'
import glob, os, sys, yaml

project_path, rendered_dir = sys.argv[1], sys.argv[2]
project = yaml.safe_load(open(project_path, encoding="utf-8"))
spec = project.get("spec", {})
permitted = {
    entry.get("kind")
    for key in ("clusterResourceWhitelist", "namespaceResourceWhitelist")
    for entry in (spec.get(key) or [])
}

rendered = set()
for path in glob.glob(os.path.join(rendered_dir, "*.yaml")):
    if os.path.basename(path).startswith(("cluster-", "phase-", "helm-")):
        continue
    for document in yaml.safe_load_all(open(path, encoding="utf-8")):
        if document and document.get("kind"):
            rendered.add(document["kind"])

for kind in sorted(rendered - permitted):
    print(kind)
PY
  )"

  if [[ -z "${missing}" ]]; then
    pass 'every rendered kind is permitted by the platform AppProject'
  else
    fail 'every rendered kind is permitted by the platform AppProject' \
      "$(printf 'not whitelisted: %s\n' ${missing})"$'\n''Argo CD would refuse these at sync time, not at review time.'
  fi
}

check_resources_are_bounded() {
  local unbounded

  unbounded="$(
    "${PYTHON}" - "${TEMPORARY_DIRECTORY}/prometheus.yaml" \
      "${TEMPORARY_DIRECTORY}/grafana.yaml" \
      "${TEMPORARY_DIRECTORY}/postgres-exporter.yaml" \
      "${TEMPORARY_DIRECTORY}/redis-exporter.yaml" \
      "${TEMPORARY_DIRECTORY}/loki.yaml" \
      "${TEMPORARY_DIRECTORY}/alloy.yaml" <<'PY'
import sys, yaml

offenders = []
for path in sys.argv[1:]:
    try:
        documents = list(yaml.safe_load_all(open(path, encoding="utf-8")))
    except FileNotFoundError:
        continue
    for document in documents:
        if not document or document.get("kind") not in (
            "Deployment", "DaemonSet", "StatefulSet"
        ):
            continue
        spec = document["spec"]["template"]["spec"]
        for container in spec.get("containers", []):
            resources = container.get("resources") or {}
            if not resources.get("requests") or not resources.get("limits"):
                offenders.append(
                    f"{document['kind']}/{document['metadata']['name']}"
                    f"/{container['name']}"
                )
print("\n".join(offenders))
PY
  )"

  if [[ -z "${unbounded}" ]]; then
    pass 'every observability container declares requests and limits'
  else
    fail 'every observability container declares requests and limits' \
      "${unbounded}"$'\n''An unbounded container can starve the workloads it observes.'
  fi
}

usage() {
  cat <<'EOF'
Usage: validate-observability.sh [--gitops-dir DIR]

  --gitops-dir DIR   Path to a NovaShop-GitOps checkout. Enables the AppProject
                     permission check, which is skipped without it.
EOF
}

main() {
  while (( $# > 0 )); do
    case "$1" in
      --gitops-dir)
        [[ $# -ge 2 ]] || die 'Option --gitops-dir requires a value.'
        GITOPS_DIR="$2"
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

  require_command helm
  resolve_python
  require_command docker

  [[ -d "${OBSERVABILITY_DIR}" ]] \
    || die "Observability values not found: ${OBSERVABILITY_DIR}"

  TEMPORARY_DIRECTORY="$(mktemp -d)"

  render_charts || true
  if [[ -s "${TEMPORARY_DIRECTORY}/prometheus.yaml" ]]; then
    check_prometheus_config
    check_required_jobs
    check_traefik_uses_pod_discovery
  fi
  check_exporters_are_discoverable
  check_loki_is_single_binary
  check_kinds_are_permitted
  check_resources_are_bounded

  if (( FAIL_COUNT > 0 )); then
    printf '[validate-observability] RESULT: FAIL (%d passed, %d failed)\n' \
      "${PASS_COUNT}" "${FAIL_COUNT}" >&2
    exit 1
  fi

  printf '[validate-observability] RESULT: PASS (%d passed, 0 failed)\n' \
    "${PASS_COUNT}"
}

main "$@"
