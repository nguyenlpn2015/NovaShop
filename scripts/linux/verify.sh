#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

export PATH="${HOME}/.local/bin:${PATH}"

readonly KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
readonly EXPECTED_NODE_IP="${NODE_IP:-10.10.1.45}"
readonly REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-30}"
readonly MAX_HTTP_LATENCY_MS="${MAX_HTTP_LATENCY_MS:-500}"
readonly MINIMUM_FREE_DISK_PERCENT="${MINIMUM_FREE_DISK_PERCENT:-15}"
readonly TLS_PHASE_ENABLED="${TLS_PHASE_ENABLED:-false}"
readonly TLS_ISSUER_NAME="${TLS_ISSUER_NAME:-letsencrypt-staging}"
readonly TLS_PRODUCTION_ENABLED="${TLS_PRODUCTION_ENABLED:-false}"
readonly ENVIRONMENTS=(development staging production)

declare -Ar FRONTEND_HOSTS=(
  [development]="dev.novashop.smartdev.vn"
  [staging]="staging.novashop.smartdev.vn"
  [production]="novashop.smartdev.vn"
)

declare -Ar BACKEND_HOSTS=(
  [development]="api.dev.novashop.smartdev.vn"
  [staging]="api.staging.novashop.smartdev.vn"
  [production]="api.novashop.smartdev.vn"
)

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[linux/verify] PASS: %s\n' "$1"
}

fail() {
  local label="$1"
  local detail="${2:-}"

  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[linux/verify] FAIL: %s\n' "${label}" >&2
  if [[ -n "${detail}" ]]; then
    printf '[linux/verify]       %s\n' "${detail}" >&2
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

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

node_ip_matches() {
  local node_ip

  node_ip="$(
    kubectl get nodes \
      --output=jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'
  )"
  [[ "${node_ip}" == "${EXPECTED_NODE_IP}" ]]
}

application_status_is() {
  local application="$1"
  local field="$2"
  local expected="$3"
  local actual

  actual="$(
    kubectl get application "${application}" \
      --namespace argocd \
      --output="jsonpath={.status.${field}}"
  )"
  [[ "${actual}" == "${expected}" ]]
}

clusterissuer_is_ready() {
  [[ "$(
    kubectl get clusterissuer "${TLS_ISSUER_NAME}" \
      --output=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  )" == "True" ]]
}

certificate_is_ready() {
  local environment="$1"

  [[ "$(
    kubectl get "certificate/novashop-${environment}-tls" \
      --namespace "novashop-${environment}" \
      --output=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  )" == "True" ]]
}

tls_secret_is_valid() {
  local environment="$1"
  local namespace="novashop-${environment}"
  local secret="novashop-${environment}-tls"
  local secret_type
  local certificate_data
  local key_data

  secret_type="$(
    kubectl get secret "${secret}" \
      --namespace "${namespace}" \
      --output=jsonpath='{.type}'
  )"
  certificate_data="$(
    kubectl get secret "${secret}" \
      --namespace "${namespace}" \
      --output=jsonpath='{.data.tls\.crt}'
  )"
  key_data="$(
    kubectl get secret "${secret}" \
      --namespace "${namespace}" \
      --output=jsonpath='{.data.tls\.key}'
  )"

  [[ "${secret_type}" == "kubernetes.io/tls" ]]
  [[ -n "${certificate_data}" ]]
  [[ -n "${key_data}" ]]
}

ingress_routes_hosts() {
  local environment="$1"
  local namespace="novashop-${environment}"
  local frontend_host="${FRONTEND_HOSTS[${environment}]}"
  local backend_host="${BACKEND_HOSTS[${environment}]}"
  local hosts

  hosts="$(
    kubectl get ingress novashop-public-http \
      --namespace "${namespace}" \
      --output=jsonpath='{.spec.rules[*].host}'
  )"

  [[ " ${hosts} " == *" ${frontend_host} "* ]]
  [[ " ${hosts} " == *" ${backend_host} "* ]]
}

dns_resolves() {
  getent ahostsv4 "$1" >/dev/null
}

http_returns_200_within_threshold() {
  local hostname="$1"
  local path="${2:-/}"
  local result
  local status
  local latency_seconds

  result="$(
    curl --silent \
      --show-error \
      --max-time "${REQUEST_TIMEOUT}" \
      --output /dev/null \
      --write-out '%{http_code} %{time_total}' \
      "http://${hostname}${path}"
  )"
  read -r status latency_seconds <<<"${result}"
  [[ "${status}" == "200" ]]
  awk -v latency="${latency_seconds}" \
    -v maximum_ms="${MAX_HTTP_LATENCY_MS}" \
    'BEGIN { exit !((latency * 1000) < maximum_ms) }'
}

http_redirects() {
  local hostname="$1"
  local status

  status="$(
    curl --silent \
      --show-error \
      --max-time "${REQUEST_TIMEOUT}" \
      --output /dev/null \
      --write-out '%{http_code}' \
      "http://${hostname}/"
  )"
  [[ "${status}" =~ ^30[1278]$ ]]
}

https_returns_200() {
  local url="$1"
  local status
  local -a tls_options=()

  if [[ "${TLS_ISSUER_NAME}" == "letsencrypt-staging" ]]; then
    tls_options+=(--insecure)
  fi

  status="$(
    curl --silent \
      --show-error \
      "${tls_options[@]}" \
      --max-time "${REQUEST_TIMEOUT}" \
      --output /dev/null \
      --write-out '%{http_code}' \
      "${url}"
  )"
  [[ "${status}" == "200" ]]
}

security_header_exists() {
  local hostname="$1"
  local header="$2"
  local scheme="${3:-http}"
  local -a tls_options=()

  if [[ "${scheme}" == "https" \
    && "${TLS_ISSUER_NAME}" == "letsencrypt-staging" ]]; then
    tls_options+=(--insecure)
  fi

  curl --silent \
    --show-error \
    "${tls_options[@]}" \
    --max-time "${REQUEST_TIMEOUT}" \
    --head \
    "${scheme}://${hostname}/" \
    | grep --ignore-case --quiet "^${header}:"
}

disk_capacity_is_healthy() {
  local used_percent

  used_percent="$(df --output=pcent / | tail --lines=1 | tr --delete ' %')"
  (( used_percent <= (100 - MINIMUM_FREE_DISK_PERCENT) ))
}

memory_is_available() {
  (( $(free --bytes | awk '/^Mem:/ { print $7 }') > 0 ))
}

certificate_expiry_is_healthy() {
  local environment="$1"
  local namespace="novashop-${environment}"
  local not_after
  local expires_epoch
  local now_epoch
  local days_remaining

  not_after="$(
    kubectl get secret "novashop-${environment}-tls" \
      --namespace "${namespace}" \
      --output=jsonpath='{.data.tls\.crt}' \
      | base64 --decode \
      | openssl x509 -noout -enddate \
      | cut --delimiter='=' --fields=2-
  )"
  expires_epoch="$(date --date="${not_after}" +%s)"
  now_epoch="$(date +%s)"
  days_remaining=$(( (expires_epoch - now_epoch) / 86400 ))
  (( days_remaining > 0 ))
  pass "Certificate in ${namespace} expires in ${days_remaining} days"
}

main() {
  local command_name
  local environment
  local namespace
  local application
  local frontend_host
  local backend_host
  local header_scheme="http"
  local preflight_failures

  for command_name in argocd awk curl df free getent grep helm kubectl systemctl; do
    run_check \
      "required command is available: ${command_name}" \
      command_exists "${command_name}"
  done
  if [[ "${TLS_PHASE_ENABLED}" == "true" ]]; then
    for command_name in base64 cut date openssl; do
      run_check \
        "TLS validation command is available: ${command_name}" \
        command_exists "${command_name}"
    done
  fi

  preflight_failures="${FAIL_COUNT}"
  if (( preflight_failures > 0 )); then
    printf '[linux/verify] RESULT: FAIL (%d passed, %d failed)\n' \
      "${PASS_COUNT}" "${FAIL_COUNT}" >&2
    exit 1
  fi

  run_check "kubeconfig is readable" test -r "${KUBECONFIG}"
  run_check "k3s service is active" systemctl is-active --quiet k3s
  run_check "Kubernetes API is reachable" kubectl cluster-info
  run_check \
    "all Kubernetes nodes are Ready" \
    kubectl wait --for=condition=Ready node --all --timeout=2m
  run_check "k3s node IP is ${EXPECTED_NODE_IP}" node_ip_matches
  run_check \
    "root filesystem has at least ${MINIMUM_FREE_DISK_PERCENT}% free" \
    disk_capacity_is_healthy
  run_check "memory is available" memory_is_available

  run_check \
    "Traefik deployment is Available" \
    kubectl wait \
      --namespace kube-system \
      --for=condition=Available \
      deployment/traefik \
      --timeout=2m

  run_check \
    "Argo CD deployments are Available" \
    kubectl wait \
      --namespace argocd \
      --for=condition=Available \
      deployment \
      --all \
      --timeout=2m

  run_check \
    "Argo CD Application novashop-root is Synced" \
    application_status_is "novashop-root" "sync.status" "Synced"
  run_check \
    "Argo CD Application novashop-root is Healthy" \
    application_status_is "novashop-root" "health.status" "Healthy"

  if [[ "${TLS_PHASE_ENABLED}" == "true" ]]; then
    for application in novashop-cert-manager novashop-certificates; do
      run_check \
        "Argo CD Application ${application} is Synced" \
        application_status_is "${application}" "sync.status" "Synced"
      run_check \
        "Argo CD Application ${application} is Healthy" \
        application_status_is "${application}" "health.status" "Healthy"
    done

    run_check \
      "cert-manager namespace exists" \
      kubectl get namespace cert-manager
    run_check \
      "cert-manager deployments are Available" \
      kubectl wait \
        --namespace cert-manager \
        --for=condition=Available \
        deployment \
        --all \
        --timeout=2m
    run_check \
      "Let's Encrypt ClusterIssuer ${TLS_ISSUER_NAME} is Ready" \
      clusterissuer_is_ready
    header_scheme="https"
  else
    pass "TLS phase is disabled; cert-manager installation is intentionally skipped"
  fi

  for environment in "${ENVIRONMENTS[@]}"; do
    namespace="novashop-${environment}"
    application="novashop-${environment}"
    frontend_host="${FRONTEND_HOSTS[${environment}]}"
    backend_host="${BACKEND_HOSTS[${environment}]}"

    run_check \
      "namespace exists: ${namespace}" \
      kubectl get namespace "${namespace}"
    run_check \
      "runtime Secret exists: ${namespace}/${namespace}-secrets" \
      kubectl get secret "${namespace}-secrets" --namespace "${namespace}"
    run_check \
      "all Pods are Ready in ${namespace}" \
      kubectl wait \
        --namespace "${namespace}" \
        --for=condition=Ready \
        pod \
        --all \
        --timeout=2m
    run_check \
      "all Deployments are Available in ${namespace}" \
      kubectl wait \
        --namespace "${namespace}" \
        --for=condition=Available \
        deployment \
        --all \
        --timeout=2m
    run_check \
      "Argo CD Application ${application} is Synced" \
      application_status_is "${application}" "sync.status" "Synced"
    run_check \
      "Argo CD Application ${application} is Healthy" \
      application_status_is "${application}" "health.status" "Healthy"
    run_check \
      "HTTP Ingress routes expected hosts in ${namespace}" \
      ingress_routes_hosts "${environment}"
    run_check \
      "DNS resolves: ${frontend_host}" \
      dns_resolves "${frontend_host}"
    run_check \
      "DNS resolves: ${backend_host}" \
      dns_resolves "${backend_host}"
    run_check \
      "frontend HTTP returns 200 in under ${MAX_HTTP_LATENCY_MS}ms: ${frontend_host}" \
      http_returns_200_within_threshold "${frontend_host}"
    run_check \
      "backend health HTTP returns 200 in under ${MAX_HTTP_LATENCY_MS}ms: ${backend_host}/health" \
      http_returns_200_within_threshold "${backend_host}" "/health"

    if [[ "${TLS_PHASE_ENABLED}" == "true" ]]; then
      run_check \
        "Certificate is Ready in ${namespace}" \
        certificate_is_ready "${environment}"
      run_check \
        "TLS Secret is valid in ${namespace}" \
        tls_secret_is_valid "${environment}"
      certificate_expiry_is_healthy "${environment}" \
        || fail "Certificate expiry is valid in ${namespace}"
      run_check \
        "frontend HTTPS returns 200: ${frontend_host}" \
        https_returns_200 "https://${frontend_host}/"
      run_check \
        "backend health HTTPS returns 200: ${backend_host}/health" \
        https_returns_200 "https://${backend_host}/health"
      if [[ "${TLS_PRODUCTION_ENABLED}" == "true" ]]; then
        run_check \
          "HTTP redirects to HTTPS: ${frontend_host}" \
          http_redirects "${frontend_host}"
      fi
    fi
  done

  if [[ "${TLS_PRODUCTION_ENABLED}" == "true" ]]; then
    run_check \
      "HSTS header is present" \
      security_header_exists "${FRONTEND_HOSTS[production]}" \
        "strict-transport-security" \
        "https"
  fi
  run_check \
    "X-Content-Type-Options header is present" \
    security_header_exists "${FRONTEND_HOSTS[production]}" \
      "x-content-type-options" \
      "${header_scheme}"
  run_check \
    "X-Frame-Options header is present" \
    security_header_exists "${FRONTEND_HOSTS[production]}" \
      "x-frame-options" \
      "${header_scheme}"
  run_check \
    "Referrer-Policy header is present" \
    security_header_exists "${FRONTEND_HOSTS[production]}" \
      "referrer-policy" \
      "${header_scheme}"
  run_check \
    "Permissions-Policy header is present" \
    security_header_exists "${FRONTEND_HOSTS[production]}" \
      "permissions-policy" \
      "${header_scheme}"

  if (( FAIL_COUNT > 0 )); then
    printf '[linux/verify] RESULT: FAIL (%d passed, %d failed)\n' \
      "${PASS_COUNT}" "${FAIL_COUNT}" >&2
    exit 1
  fi

  printf '[linux/verify] RESULT: PASS (%d passed, 0 failed)\n' \
    "${PASS_COUNT}"
}

main "$@"
