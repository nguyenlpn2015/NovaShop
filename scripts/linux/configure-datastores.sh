#!/usr/bin/env bash

# Makes the host PostgreSQL and Redis reachable by cluster workloads.
#
# Both datastores run on the node rather than inside the cluster, and both were
# left listening on the loopback interface only. Pods therefore could not reach
# them at all: a socket test from a production pod returned ConnectionRefusedError
# for 5432 and 6379. Nothing detected this, because the application health
# endpoint answered without touching either dependency.
#
# Redis carried a second, independent defect. The connection string issued to
# workloads contains a password, but the server had no `requirepass`, so it
# rejects AUTH outright. Fixing reachability alone would have produced a
# different failure at the next layer.
#
# This script is idempotent: it rewrites only the directives it owns, marked with
# a managed block, and restarts a service only when its configuration changed.
#
# Firewalling is deliberately opt-in. See the ENABLE_UFW note in main().

set -Eeuo pipefail
IFS=$'\n\t'

readonly PLATFORM_ENV_FILE="${PLATFORM_ENV_FILE:-/root/.novashop-platform.env}"
readonly NODE_IP="${NODE_IP:-10.10.1.45}"
readonly POD_CIDR="${POD_CIDR:-10.42.0.0/16}"
readonly POSTGRES_VERSION="${POSTGRES_VERSION:-14}"
readonly POSTGRES_CONF="${POSTGRES_CONF:-/etc/postgresql/${POSTGRES_VERSION}/main/postgresql.conf}"
readonly POSTGRES_HBA="${POSTGRES_HBA:-/etc/postgresql/${POSTGRES_VERSION}/main/pg_hba.conf}"
readonly REDIS_CONF="${REDIS_CONF:-/etc/redis/redis.conf}"
readonly ENABLE_UFW="${ENABLE_UFW:-false}"
readonly MANAGEMENT_CIDR="${MANAGEMENT_CIDR:-}"
readonly MARKER='# managed by novashop configure-datastores.sh'

POSTGRES_CHANGED=false
REDIS_CHANGED=false

log() {
  printf '[configure-datastores] %s\n' "$*"
}

die() {
  printf '[configure-datastores] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_root() {
  [[ "$(id -u)" == "0" ]] || die 'This script must run as root.'
}

# Credentials are read from the platform environment file rather than passed on
# the command line, so they never appear in the process list or shell history.
load_platform_environment() {
  local file_mode

  [[ -r "${PLATFORM_ENV_FILE}" ]] \
    || die "Platform environment file is not readable: ${PLATFORM_ENV_FILE}"
  file_mode="$(stat --format='%a' "${PLATFORM_ENV_FILE}")"
  (( (8#${file_mode} & 8#077) == 0 )) \
    || die "Platform environment file must not be group or world accessible; run: chmod 600 ${PLATFORM_ENV_FILE}"

  set -a
  # shellcheck disable=SC1090
  source "${PLATFORM_ENV_FILE}"
  set +a

  [[ -n "${DATABASE_URL:-}" ]] || die "DATABASE_URL is missing from ${PLATFORM_ENV_FILE}."
  [[ -n "${REDIS_URL:-}" ]] || die "REDIS_URL is missing from ${PLATFORM_ENV_FILE}."
}

# Percent-encoding is legal in a connection URL, so the password is decoded with
# a real URL parser instead of string splitting.
redis_password_from_url() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import urlsplit, unquote
password = urlsplit(sys.argv[1]).password
sys.stdout.write(unquote(password) if password else "")
PY
}

backup_once() {
  local path="$1"

  [[ -f "${path}.novashop.bak" ]] && return 0
  cp --archive "${path}" "${path}.novashop.bak"
  log "Backed up ${path} to ${path}.novashop.bak"
}

# Replaces the managed block if present, appends it otherwise. Directives outside
# the block are never touched, so operator changes survive a rerun.
apply_managed_block() {
  local path="$1"
  local body="$2"
  local rendered
  local current

  rendered="${MARKER} BEGIN"$'\n'"${body}"$'\n'"${MARKER} END"

  if grep -Fq "${MARKER} BEGIN" "${path}"; then
    current="$(
      sed -n "/${MARKER} BEGIN/,/${MARKER} END/p" "${path}"
    )"
    if [[ "${current}" == "${rendered}" ]]; then
      return 1
    fi
    sed -i "/${MARKER} BEGIN/,/${MARKER} END/d" "${path}"
  fi

  printf '%s\n' "${rendered}" >>"${path}"
  return 0
}

configure_postgres() {
  local body

  [[ -f "${POSTGRES_CONF}" ]] || die "Not found: ${POSTGRES_CONF}"
  [[ -f "${POSTGRES_HBA}" ]] || die "Not found: ${POSTGRES_HBA}"
  backup_once "${POSTGRES_CONF}"
  backup_once "${POSTGRES_HBA}"

  # Loopback is kept so existing local tooling and peer authentication continue
  # to work unchanged.
  body="listen_addresses = 'localhost,${NODE_IP}'"
  if apply_managed_block "${POSTGRES_CONF}" "${body}"; then
    POSTGRES_CHANGED=true
    log "Set listen_addresses to localhost,${NODE_IP}."
  else
    log 'PostgreSQL listen_addresses already correct.'
  fi

  # pg_hba is the authorisation boundary that matters here. Opening the port
  # without this rule would leave pods rejected; adding the rule without
  # restricting the source would accept the whole /16 the node sits on.
  body="host    all    all    ${POD_CIDR}    scram-sha-256"
  if apply_managed_block "${POSTGRES_HBA}" "${body}"; then
    POSTGRES_CHANGED=true
    log "Authorised ${POD_CIDR} in pg_hba.conf with scram-sha-256."
  else
    log 'PostgreSQL host-based authorisation already correct.'
  fi
}

configure_redis() {
  local password
  local body

  [[ -f "${REDIS_CONF}" ]] || die "Not found: ${REDIS_CONF}"
  password="$(redis_password_from_url "${REDIS_URL}")"
  [[ -n "${password}" ]] \
    || die 'REDIS_URL contains no password. Refusing to expose Redis beyond loopback without authentication.'

  backup_once "${REDIS_CONF}"

  # Once bind names a non-loopback address, protected-mode no longer guards the
  # server, so requirepass is what stands between the pod network and the data.
  # The password comes from the same URL the workloads already use, which is why
  # AUTH currently fails against a server that has none configured.
  body="bind 127.0.0.1 ::1 ${NODE_IP}"$'\n'"requirepass ${password}"
  if apply_managed_block "${REDIS_CONF}" "${body}"; then
    REDIS_CHANGED=true
    log "Bound Redis to loopback and ${NODE_IP}, and enabled requirepass."
  else
    log 'Redis bind and authentication already correct.'
  fi

  chown redis:redis "${REDIS_CONF}"
  chmod 0640 "${REDIS_CONF}"
}

restart_changed_services() {
  if [[ "${POSTGRES_CHANGED}" == "true" ]]; then
    log 'Restarting PostgreSQL; listen_addresses cannot be applied by reload.'
    systemctl restart "postgresql@${POSTGRES_VERSION}-main"
    systemctl is-active --quiet "postgresql@${POSTGRES_VERSION}-main" \
      || die 'PostgreSQL failed to start. Restore the .novashop.bak files and investigate.'
  fi

  if [[ "${REDIS_CHANGED}" == "true" ]]; then
    log 'Restarting Redis.'
    systemctl restart redis-server
    systemctl is-active --quiet redis-server \
      || die 'Redis failed to start. Restore the .novashop.bak file and investigate.'
  fi
}

verify() {
  local password
  local failures=0

  password="$(redis_password_from_url "${REDIS_URL}")"

  if ss -ltn "sport = :5432" | grep -Fq "${NODE_IP}:5432"; then
    log "PASS PostgreSQL is listening on ${NODE_IP}:5432."
  else
    printf '[configure-datastores] FAIL PostgreSQL is not listening on %s:5432\n' "${NODE_IP}" >&2
    failures=$((failures + 1))
  fi

  if ss -ltn "sport = :6379" | grep -Fq "${NODE_IP}:6379"; then
    log "PASS Redis is listening on ${NODE_IP}:6379."
  else
    printf '[configure-datastores] FAIL Redis is not listening on %s:6379\n' "${NODE_IP}" >&2
    failures=$((failures + 1))
  fi

  if redis-cli -h "${NODE_IP}" -a "${password}" --no-auth-warning ping 2>/dev/null \
    | grep -Fqx PONG; then
    log 'PASS Redis accepts the configured password.'
  else
    printf '[configure-datastores] FAIL Redis rejected the configured password.\n' >&2
    failures=$((failures + 1))
  fi

  # An unauthenticated client must not be served once the port leaves loopback.
  if redis-cli -h "${NODE_IP}" ping 2>&1 | grep -Fq NOAUTH; then
    log 'PASS Redis refuses unauthenticated clients.'
  else
    printf '[configure-datastores] FAIL Redis answered an unauthenticated client.\n' >&2
    failures=$((failures + 1))
  fi

  (( failures == 0 )) || die "${failures} verification check(s) failed."
}

# UFW is opt-in and refuses to run without an explicit management CIDR.
#
# Enabling a default-deny firewall over SSH locks the operator out whenever the
# allowed range does not contain their real source address, and that address is
# frequently not the range the node sits in. Run this from the console, or after
# confirming your source with: echo "${SSH_CONNECTION}".
configure_firewall() {
  if [[ "${ENABLE_UFW}" != "true" ]]; then
    log 'Firewall unchanged. Set ENABLE_UFW=true with MANAGEMENT_CIDR to enable it.'
    return
  fi

  [[ -n "${MANAGEMENT_CIDR}" ]] \
    || die 'ENABLE_UFW=true requires MANAGEMENT_CIDR covering your administrative source address.'

  require_command ufw
  log "Allowing SSH from ${MANAGEMENT_CIDR} before enabling the firewall."
  ufw allow from "${MANAGEMENT_CIDR}" to any port 22 proto tcp
  ufw allow from "${MANAGEMENT_CIDR}" to any port 6443 proto tcp
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow from "${POD_CIDR}"
  ufw allow from 10.43.0.0/16
  ufw default deny incoming
  ufw default allow outgoing
  ufw --force enable
  ufw status verbose
}

main() {
  require_root
  require_command python3
  require_command redis-cli
  require_command ss
  require_command systemctl

  load_platform_environment
  configure_postgres
  configure_redis
  restart_changed_services
  verify
  configure_firewall

  log 'Host datastores are reachable by cluster workloads.'
}

main "$@"
