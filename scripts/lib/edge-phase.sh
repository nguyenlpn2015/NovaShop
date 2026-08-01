#!/usr/bin/env bash

# Shared edge-phase detection for the Linux entry points.
#
# The GitOps repository is the only place that decides which edge phase is
# active. Bootstrap, recovery, and verification therefore observe the reconciled
# Application instead of being told through environment variables, so a rerun
# after a reviewed rollback validates the phase that is actually live rather than
# the phase the operator remembered.
#
# This file is sourced, never executed.

# shellcheck shell=bash

readonly EDGE_PHASE_ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

edge_phase_kubectl() {
  if [[ -n "${KUBE_CONTEXT:-}" ]]; then
    kubectl --context "${KUBE_CONTEXT}" "$@"
  else
    kubectl "$@"
  fi
}

# Emits: enforced | baseline | http | none | unknown
detect_edge_phase() {
  local source_path

  source_path="$(
    edge_phase_kubectl get application novashop-production \
      --namespace "${EDGE_PHASE_ARGOCD_NAMESPACE}" \
      --output=jsonpath='{range .spec.sources[*]}{.path}{"\n"}{end}' \
      2>/dev/null \
      | grep '^kubernetes/ingress/' \
      | head -n 1 \
      || true
  )"

  case "${source_path}" in
    kubernetes/ingress/examples) printf 'enforced' ;;
    kubernetes/ingress/baseline) printf 'baseline' ;;
    kubernetes/ingress/http) printf 'http' ;;
    '') printf 'none' ;;
    *) printf 'unknown' ;;
  esac
}

# Exports the verification contract that matches the supplied phase. Returns
# non-zero for a phase that cannot be verified, so callers fail closed.
export_verification_environment() {
  local phase="$1"

  case "${phase}" in
    enforced)
      export EDGE_PHASE=enforced
      export TLS_PHASE_ENABLED=true
      export TLS_PRODUCTION_ENABLED=true
      export TLS_ISSUER_NAME=letsencrypt-production
      ;;
    baseline)
      export EDGE_PHASE=baseline
      export TLS_PHASE_ENABLED=true
      export TLS_PRODUCTION_ENABLED=false
      export TLS_ISSUER_NAME=letsencrypt-production
      ;;
    http)
      export EDGE_PHASE=http
      export TLS_PHASE_ENABLED=false
      export TLS_PRODUCTION_ENABLED=false
      ;;
    *)
      return 1
      ;;
  esac
}
