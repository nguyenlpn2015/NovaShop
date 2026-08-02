#!/usr/bin/env bash

# Restores PostgreSQL and the k3s datastore from a backup-datastores.sh set.
#
# The counterpart to scripts/restore-platform-state.sh, which restores certificate Secrets.
# Both are needed; neither covers what the other does.
#
# Two properties matter more than anything else here, because this runs when production is
# already down and the operator is under pressure:
#
#   It verifies before it acts. Every precondition is checked and reported together, so the
#   answer is either "proceed" or "here is what is missing" — never a half-applied restore
#   that has to be diagnosed on top of the original outage.
#
#   It refuses to overwrite data by accident. Restoring PostgreSQL over a database that
#   already has tables requires --force, because the common mistake is running this against
#   a healthy node.
#
# Ordering, which is not negotiable:
#
#   PostgreSQL data is restored before the application serves traffic. The backend's /ready
#   probe checks that PostgreSQL is *reachable*, not that it has data — so a skipped restore
#   produces Ready pods, Healthy Applications, silent alerts, and an empty database.
#
#   The k3s datastore is restored only with k3s stopped. Writing to a live SQLite file that
#   the API server has open corrupts it.

set -Eeuo pipefail
IFS=$'\n\t'

readonly POSTGRES_SUPERUSER="${POSTGRES_SUPERUSER:-postgres}"
readonly K3S_DATABASE="${K3S_DATABASE:-/var/lib/rancher/k3s/server/db/state.db}"
readonly PLATFORM_ENV_FILE="${PLATFORM_ENV_FILE:-/root/.novashop-platform.env}"

BACKUP_DIRECTORY=""
RESTORE_POSTGRES=true
RESTORE_K3S=false
RESTORE_ENVIRONMENT=false
FORCE=false
DRY_RUN=false
TARGET_DATABASE=""
PRECONDITION_FAILURES=0

log() {
  printf '[restore-datastores] %s\n' "$*"
}

warn() {
  printf '[restore-datastores] WARNING: %s\n' "$*" >&2
}

die() {
  printf '[restore-datastores] ERROR: %s\n' "$*" >&2
  exit 1
}

ok() {
  printf '[restore-datastores]   ok    %s\n' "$*"
}

bad() {
  PRECONDITION_FAILURES=$((PRECONDITION_FAILURES + 1))
  printf '[restore-datastores]   FAIL  %s\n' "$*" >&2
}

usage() {
  cat <<'USAGE'
Usage: restore-datastores.sh --from BACKUP_DIR [options]

  --from DIR           A timestamped directory produced by backup-datastores.sh.
  --database NAME      Restore into this database instead of the one recorded in the dump.
                       Used by the rehearsal to restore into a scratch database.
  --include-k3s        Also restore the k3s datastore. Stops k3s, replaces the file, starts
                       it. Omit on a fresh node: bootstrap plus Argo CD rebuilds the cluster
                       from Git, which is the better path.
  --include-environment
                       Also restore /root/.novashop-platform.env. Omit if the file on this
                       node is already correct.
  --force              Restore over a database that already contains tables.
  --dry-run            Run every precondition and report what would happen. Changes nothing.
  -h, --help           This message.

Must run as root.

Run scripts/verify-backup.sh on the set first. This script re-checks the essentials, but
verify-backup checks more and costs seconds.
USAGE
}

require_root() {
  [[ "$(id -u)" == "0" ]] || die 'Must run as root.'
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# Everything is checked before anything is changed. A restore that stops halfway has
# produced a third state that is neither the old one nor the new one, and now that has to be
# diagnosed too — during an outage.
run_preconditions() {
  log 'Preconditions:'

  if [[ -d "${BACKUP_DIRECTORY}" ]]; then
    ok "backup directory exists: ${BACKUP_DIRECTORY}"
  else
    bad "backup directory not found: ${BACKUP_DIRECTORY}"
    return
  fi

  if [[ -r "${BACKUP_DIRECTORY}/manifest.txt" ]]; then
    ok 'manifest is readable'
  else
    bad 'manifest.txt is missing; this may not be a backup-datastores.sh set'
  fi

  local dumps=()
  shopt -s nullglob
  dumps=("${BACKUP_DIRECTORY}"/postgresql-*.dump)
  shopt -u nullglob

  if [[ "${RESTORE_POSTGRES}" == "true" ]]; then
    if (( ${#dumps[@]} > 0 )); then
      ok "${#dumps[@]} PostgreSQL dump(s) present"
    else
      bad 'no postgresql-*.dump in the set'
    fi

    if ( cd / && su -s /bin/sh "${POSTGRES_SUPERUSER}" -c 'psql -tAc "SELECT 1"' ) >/dev/null 2>&1; then
      ok 'PostgreSQL is reachable'
    else
      bad 'PostgreSQL is not reachable; start it before restoring'
    fi
  fi

  if [[ "${RESTORE_K3S}" == "true" ]]; then
    if [[ -f "${BACKUP_DIRECTORY}/k3s-state.db" ]]; then
      local integrity
      integrity="$(sqlite3 "${BACKUP_DIRECTORY}/k3s-state.db" 'PRAGMA integrity_check;' 2>&1 || true)"
      if [[ "${integrity}" == "ok" ]]; then
        ok 'k3s datastore copy passes integrity_check'
      else
        bad "k3s datastore copy fails integrity_check: ${integrity}"
      fi
    else
      bad 'no k3s-state.db in the set but --include-k3s was requested'
    fi
  fi

  if [[ "${RESTORE_ENVIRONMENT}" == "true" && ! -f "${BACKUP_DIRECTORY}/platform-environment.env" ]]; then
    bad 'no platform-environment.env in the set but --include-environment was requested'
  fi

  (( PRECONDITION_FAILURES == 0 )) \
    || die "${PRECONDITION_FAILURES} precondition(s) failed. Nothing has been changed."

  log 'All preconditions passed.'
}

database_has_tables() {
  local database="$1"
  local count

  count="$(
    su -s /bin/sh "${POSTGRES_SUPERUSER}" -c \
      "psql -tAd '${database}' -c \"SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema');\"" \
      2>/dev/null | tr -d '[:space:]'
  )"

  [[ -n "${count}" && "${count}" != "0" ]]
}

restore_database() {
  local dump="$1"
  local name database

  name="$(basename -- "${dump}")"
  database="${TARGET_DATABASE:-${name#postgresql-}}"
  database="${database%.dump}"

  log "Restoring ${name} into database '${database}'."

  if ! su -s /bin/sh "${POSTGRES_SUPERUSER}" -c \
    "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='${database}'\"" 2>/dev/null | grep -q 1; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      log "  would create database '${database}'"
    else
      log "  creating database '${database}'"
      cd / && su -s /bin/sh "${POSTGRES_SUPERUSER}" -c "createdb '${database}'" \
        || die "Could not create ${database}."
    fi
  elif database_has_tables "${database}"; then
    # The realistic mistake is running this against a healthy node, so it has to be refused
    # rather than warned about.
    [[ "${FORCE}" == "true" ]] \
      || die "Database '${database}' already contains tables. Pass --force to overwrite, or --database to restore into a scratch database."
    warn "'${database}' already contains tables; --force given, restoring over it."
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    log "  would run pg_restore --clean --if-exists into '${database}'"
    return 0
  fi

  # --single-transaction so a failure leaves the database as it was rather than half
  # restored. --clean --if-exists so restoring over an existing schema works without
  # erroring on the first object that already exists.
  #
  # The archive arrives on stdin rather than as a path. root opens the file and the postgres
  # process inherits the descriptor, so the backup directory stays 0700 root-owned. Passing
  # a path would mean making a directory full of database dumps readable by another user.
  # cd / for the same reason as in backup-datastores.sh.
  if ! ( cd / && su -s /bin/sh "${POSTGRES_SUPERUSER}" -c \
    "pg_restore --dbname='${database}' --clean --if-exists --no-owner --no-privileges --single-transaction" ) \
    <"${dump}" 2>/tmp/restore-datastores.err; then
    warn "pg_restore reported errors for ${database}:"
    sed 's/^/[restore-datastores]       /' /tmp/restore-datastores.err >&2
    rm -f /tmp/restore-datastores.err
    die "Restore of ${database} failed. --single-transaction means the database is unchanged."
  fi
  rm -f /tmp/restore-datastores.err

  local tables
  tables="$(
    su -s /bin/sh "${POSTGRES_SUPERUSER}" -c \
      "psql -tAd '${database}' -c \"SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog','information_schema');\"" \
      | tr -d '[:space:]'
  )"
  log "  restored: ${tables} table(s) in '${database}'."
}

# k3s must be stopped. The API server holds the SQLite file open and writes to it
# continuously; replacing it underneath a running server corrupts it.
restore_k3s_datastore() {
  local source="${BACKUP_DIRECTORY}/k3s-state.db"
  local stamp

  if [[ "${DRY_RUN}" == "true" ]]; then
    log 'would stop k3s, move the current datastore aside, install the copy, and start k3s'
    return 0
  fi

  stamp="$(date --utc +%Y%m%dT%H%M%SZ)"

  log 'Stopping k3s.'
  systemctl stop k3s || die 'Could not stop k3s.'

  if [[ -f "${K3S_DATABASE}" ]]; then
    log "Moving the current datastore aside: ${K3S_DATABASE}.${stamp}.bak"
    mv -- "${K3S_DATABASE}" "${K3S_DATABASE}.${stamp}.bak"
  fi

  install -m 0600 -o root -g root "${source}" "${K3S_DATABASE}"
  log 'Datastore installed.'

  log 'Starting k3s.'
  systemctl start k3s || die 'k3s did not start. The previous datastore is beside it with a .bak suffix.'

  local attempt
  for attempt in $(seq 1 30); do
    if k3s kubectl get --raw /readyz >/dev/null 2>&1; then
      log "k3s is serving after ${attempt} attempt(s)."
      return 0
    fi
    sleep 5
  done

  die 'k3s did not become ready. The previous datastore is beside it with a .bak suffix.'
}

restore_environment_file() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "would install platform-environment.env to ${PLATFORM_ENV_FILE}"
    return 0
  fi

  install -m 0600 -o root -g root \
    "${BACKUP_DIRECTORY}/platform-environment.env" "${PLATFORM_ENV_FILE}"
  log "Restored ${PLATFORM_ENV_FILE} (root, 0600)."
}

main() {
  while (( $# > 0 )); do
    case "$1" in
      --from)
        [[ $# -ge 2 ]] || die 'Option --from requires a value.'
        BACKUP_DIRECTORY="$2"; shift ;;
      --database)
        [[ $# -ge 2 ]] || die 'Option --database requires a value.'
        TARGET_DATABASE="$2"; shift ;;
      --include-k3s) RESTORE_K3S=true ;;
      --include-environment) RESTORE_ENVIRONMENT=true ;;
      --force) FORCE=true ;;
      --dry-run) DRY_RUN=true ;;
      -h | --help) usage; exit 0 ;;
      *) usage >&2; die "Unknown argument: $1" ;;
    esac
    shift
  done

  [[ -n "${BACKUP_DIRECTORY}" ]] || { usage >&2; die 'Option --from is required.'; }

  require_root
  require_command sqlite3
  require_command su

  BACKUP_DIRECTORY="$(cd -- "${BACKUP_DIRECTORY}" 2>/dev/null && pwd)" \
    || die "Not a directory: ${BACKUP_DIRECTORY}"

  [[ "${DRY_RUN}" == "true" ]] && log 'DRY RUN — nothing will be changed.'

  run_preconditions

  if [[ "${RESTORE_POSTGRES}" == "true" ]]; then
    local dump
    shopt -s nullglob
    for dump in "${BACKUP_DIRECTORY}"/postgresql-*.dump; do
      restore_database "${dump}"
    done
    shopt -u nullglob
  fi

  [[ "${RESTORE_ENVIRONMENT}" == "true" ]] && restore_environment_file
  [[ "${RESTORE_K3S}" == "true" ]] && restore_k3s_datastore

  if [[ "${DRY_RUN}" == "true" ]]; then
    log 'DRY RUN complete. Nothing was changed.'
    return 0
  fi

  log 'Restore complete.'
  log 'The backend /ready probe checks that PostgreSQL is reachable, not that it holds data.'
  log 'Confirm the row counts you expect before declaring recovery finished.'
}

main "$@"
