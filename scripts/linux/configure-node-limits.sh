#!/usr/bin/env bash

# Raises the kernel inotify limits the platform needs.
#
# Adding the observability stack exhausted fs.inotify.max_user_instances. The
# default is 128 and the node reached 140 in use: every config-reloader, log
# collector, dashboard sidecar, and certificate watcher consumes an instance,
# and once they are gone other workloads simply stop being able to watch files.
#
# Traefik reported it plainly:
#
#   failed to create fsnotify watcher: too many open files
#
# That is not a cosmetic log line. Traefik watches its dynamic configuration, and
# cert-manager and Argo CD watch theirs. A workload that cannot create a watcher
# keeps running with whatever it loaded at startup and silently stops noticing
# changes, which on this platform means a renewed certificate or a synced
# manifest that never takes effect.
#
# The limits are written to a sysctl.d drop-in so they survive a reboot, and the
# script is idempotent.

set -Eeuo pipefail
IFS=$'\n\t'

readonly SYSCTL_FILE="${SYSCTL_FILE:-/etc/sysctl.d/90-novashop-inotify.conf}"
readonly MAX_USER_INSTANCES="${MAX_USER_INSTANCES:-512}"
readonly MAX_USER_WATCHES="${MAX_USER_WATCHES:-524288}"

log() {
  printf '[configure-node-limits] %s\n' "$*"
}

die() {
  printf '[configure-node-limits] ERROR: %s\n' "$*" >&2
  exit 1
}

require_root() {
  [[ "$(id -u)" == "0" ]] || die 'This script must run as root.'
}

current() {
  sysctl --values "$1" 2>/dev/null || printf '0'
}

main() {
  local desired
  local instances_before
  local watches_before

  require_root
  command -v sysctl >/dev/null 2>&1 || die 'Required command not found: sysctl'

  instances_before="$(current fs.inotify.max_user_instances)"
  watches_before="$(current fs.inotify.max_user_watches)"
  log "Current: instances=${instances_before} watches=${watches_before}"

  desired="$(
    cat <<EOF
# Managed by scripts/linux/configure-node-limits.sh
#
# The default instance limit of 128 is exhausted by the observability stack on
# this node. See the script header for why an exhausted limit is a correctness
# problem and not only a log line.
fs.inotify.max_user_instances = ${MAX_USER_INSTANCES}
fs.inotify.max_user_watches = ${MAX_USER_WATCHES}
EOF
  )"

  if [[ -f "${SYSCTL_FILE}" ]] \
    && [[ "$(cat "${SYSCTL_FILE}")" == "${desired}" ]]; then
    log "${SYSCTL_FILE} is already correct."
  else
    printf '%s\n' "${desired}" >"${SYSCTL_FILE}"
    chmod 0644 "${SYSCTL_FILE}"
    log "Wrote ${SYSCTL_FILE}."
  fi

  sysctl --quiet --load="${SYSCTL_FILE}"

  local instances_after
  local watches_after
  instances_after="$(current fs.inotify.max_user_instances)"
  watches_after="$(current fs.inotify.max_user_watches)"

  (( instances_after >= MAX_USER_INSTANCES )) \
    || die "instances limit is ${instances_after}, expected at least ${MAX_USER_INSTANCES}"
  (( watches_after >= MAX_USER_WATCHES )) \
    || die "watches limit is ${watches_after}, expected at least ${MAX_USER_WATCHES}"

  log "PASS instances=${instances_after} watches=${watches_after}"

  # Workloads that already failed to create a watcher do not retry, so anything
  # that logged the failure needs a restart. The operator is told rather than
  # having pods restarted underneath them.
  log 'Any workload that already logged "too many open files" must be restarted to pick up a watcher.'
}

main "$@"
