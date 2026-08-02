#!/usr/bin/env bash

# Backs up the data this platform cannot regenerate from Git.
#
# scripts/backup-platform-state.sh exports Kubernetes Secrets — certificates and the ACME
# account key. It does not touch the datastores, and until this script existed the
# `novashop` database had no backup of any kind. Documentation claimed otherwise, which is
# how a gap survives: someone reads the claim and stops looking.
#
# What is captured, and why only this:
#
#   PostgreSQL  the only irreplaceable application data on the platform
#   k3s SQLite  rebuildable from GitOps in roughly ten minutes, so this is a convenience
#               rather than a necessity — included because it is cheap
#
# What is deliberately not captured:
#
#   Redis            a cache; losing it costs a warm-up, not data
#   local-path PVCs  550MB of Prometheus, Loki, Grafana, and Alertmanager volumes whose
#                    contents are observational and already bounded by retention. Including
#                    them would grow a backup set fifty-fold to protect data that expires
#                    on its own.
#   Everything else  reconciled from Git by Argo CD
#
# The output is a timestamped directory with a manifest carrying a SHA-256 per artefact, so
# scripts/verify-backup.sh can prove the set is intact without restoring it.

set -Eeuo pipefail
IFS=$'\n\t'

readonly PLATFORM_ENV_FILE="${PLATFORM_ENV_FILE:-/root/.novashop-platform.env}"
readonly K3S_DATABASE="${K3S_DATABASE:-/var/lib/rancher/k3s/server/db/state.db}"
readonly POSTGRES_SUPERUSER="${POSTGRES_SUPERUSER:-postgres}"
readonly SCHEMA_ONLY_TABLES="${SCHEMA_ONLY_TABLES:-}"

OUTPUT_DIRECTORY=""
DATABASES=()
INCLUDE_K3S=true
LABEL=""
BACKUP_DIRECTORY=""

log() {
  printf '[backup-datastores] %s\n' "$*"
}

warn() {
  printf '[backup-datastores] WARNING: %s\n' "$*" >&2
}

die() {
  printf '[backup-datastores] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 \
    || die "Required command not found: $1"
}

usage() {
  cat <<'USAGE'
Usage: backup-datastores.sh --output-dir DIR [options]

  --output-dir DIR     Parent directory. A timestamped subdirectory is created inside it.
  --database NAME      Database to dump. Repeatable. Defaults to every non-template database.
  --label TEXT         Recorded in the manifest. Use it to mark why an out-of-band backup
                       was taken, for example "before-schema-change".
  --skip-k3s           Do not copy the k3s datastore. The cluster is rebuildable from Git;
                       the database is not.
  -h, --help           This message.

Must run as root: it reads the k3s datastore and switches to the postgres user.

Take a backup before every schema change. That is the copy most likely to be needed.
USAGE
}

require_root() {
  [[ "$(id -u)" == "0" ]] \
    || die 'Must run as root: reads the k3s datastore and switches to the postgres user.'
}

# A backup contains database contents and, for the k3s datastore, every Secret in the
# cluster. Writing it inside a git working tree is how that ends up in a commit.
refuse_git_working_tree() {
  local directory="$1"
  local probe="${directory}"

  while [[ "${probe}" != "/" && -n "${probe}" ]]; do
    if [[ -d "${probe}/.git" ]]; then
      die "Refusing to write a backup inside the git working tree at ${probe}. It contains database contents and cluster Secrets."
    fi
    probe="$(dirname -- "${probe}")"
  done
}

discover_databases() {
  local found

  found="$(
    su -s /bin/sh "${POSTGRES_SUPERUSER}" -c \
      "psql -tAc \"SELECT datname FROM pg_database WHERE datistemplate = false AND datname <> 'postgres';\"" \
      2>/dev/null || true
  )"

  [[ -n "${found}" ]] \
    || die 'No database discovered. Pass --database explicitly, or check that PostgreSQL is running.'

  mapfile -t DATABASES <<<"${found}"
  log "Discovered database(s): ${DATABASES[*]}"
}

# pg_dump in custom format, not plain SQL.
#
# Custom format is compressed, allows pg_restore --list to prove the dump is readable
# without restoring it, and allows restoring a single table. A plain-text dump gives none
# of those and is larger.
dump_database() {
  local database="$1"
  local target="${BACKUP_DIRECTORY}/postgresql-${database}.dump"

  log "Dumping ${database}."

  # su rather than sudo -u: this script already requires root, and sudo here would need a
  # tty or an askpass in some configurations.
  #
  # cd / first. su leaves the working directory as it was, and if the caller ran this from a
  # root-only directory the postgres process cannot enter it. That produces "could not
  # change directory" on every run and, depending on the psql version, a hard failure.
  if ! ( cd / && su -s /bin/sh "${POSTGRES_SUPERUSER}" -c \
    "pg_dump --format=custom --compress=6 --no-owner --no-privileges --dbname='${database}'" ) \
    >"${target}"; then
    rm -f -- "${target}"
    die "pg_dump failed for ${database}. Nothing partial was left behind."
  fi

  chmod 0600 "${target}"

  # A dump that pg_restore cannot list is a file, not a backup. Checking now costs a second
  # and turns a silent failure into a loud one.
  #
  # Run as root, not as postgres. --list only parses the archive header and needs no
  # database connection, and the backup directory is 0700 root-owned by design — so the
  # postgres user cannot read the file. Dropping privileges here would mean loosening those
  # permissions on a directory holding database contents.
  if ! pg_restore --list "${target}" >/dev/null 2>&1; then
    die "pg_restore cannot read the dump just written for ${database}."
  fi

  log "  $(du -h "${target}" | awk '{print $1}') — readable by pg_restore."
}

# The k3s datastore must not be copied with cp.
#
# k3s writes to SQLite continuously. A byte-for-byte copy of a live database can capture a
# half-written page, and the result is a file that looks fine and is corrupt — discovered
# at the moment it is needed. The .backup command uses SQLite's online backup API, which is
# consistent under concurrent writes.
#
# k3s ships snapshot support for etcd only. Single-server k3s uses SQLite, so this has to be
# done here.
backup_k3s_datastore() {
  local target="${BACKUP_DIRECTORY}/k3s-state.db"

  if [[ ! -f "${K3S_DATABASE}" ]]; then
    warn "k3s datastore not found at ${K3S_DATABASE}; skipping. The cluster is rebuildable from Git."
    return 0
  fi

  log 'Copying the k3s datastore with the SQLite online backup API.'
  sqlite3 "${K3S_DATABASE}" ".backup '${target}'" \
    || die 'sqlite3 .backup failed.'
  chmod 0600 "${target}"

  local integrity
  integrity="$(sqlite3 "${target}" 'PRAGMA integrity_check;' 2>&1 || true)"
  [[ "${integrity}" == "ok" ]] \
    || die "The SQLite copy failed its integrity check: ${integrity}"

  log "  $(du -h "${target}" | awk '{print $1}') — integrity_check ok."
}

# The platform environment file holds the credentials nothing else can reproduce. It is the
# one artefact whose loss makes every other part of the backup unusable.
copy_platform_environment() {
  local target="${BACKUP_DIRECTORY}/platform-environment.env"

  if [[ ! -f "${PLATFORM_ENV_FILE}" ]]; then
    warn "${PLATFORM_ENV_FILE} not found. Recovery will have no credentials to restore."
    return 0
  fi

  install -m 0600 "${PLATFORM_ENV_FILE}" "${target}"
  log 'Captured the platform environment file.'
}

write_manifest() {
  local manifest="${BACKUP_DIRECTORY}/manifest.txt"
  local artefact

  {
    printf 'novashop-datastore-backup\n'
    printf 'taken_at=%s\n' "$(date --iso-8601=seconds)"
    printf 'taken_on=%s\n' "$(hostname)"
    printf 'label=%s\n' "${LABEL:-scheduled}"
    printf 'postgres_version=%s\n' \
      "$(cd / && su -s /bin/sh "${POSTGRES_SUPERUSER}" -c 'psql -tAc "SHOW server_version;"' 2>/dev/null | tr -d '[:space:]')"
    printf 'k3s_version=%s\n' "$(k3s --version 2>/dev/null | head -1 | awk '{print $3}')"
    printf 'databases=%s\n' "${DATABASES[*]}"
    printf '\n# sha256  size_bytes  artefact\n'
  } >"${manifest}"

  for artefact in "${BACKUP_DIRECTORY}"/*; do
    [[ "${artefact}" == "${manifest}" ]] && continue
    printf '%s  %s  %s\n' \
      "$(sha256sum "${artefact}" | awk '{print $1}')" \
      "$(stat -c '%s' "${artefact}")" \
      "$(basename -- "${artefact}")" \
      >>"${manifest}"
  done

  chmod 0600 "${manifest}"
  log "Manifest written with a checksum per artefact."
}

main() {
  while (( $# > 0 )); do
    case "$1" in
      --output-dir)
        [[ $# -ge 2 ]] || die 'Option --output-dir requires a value.'
        OUTPUT_DIRECTORY="$2"
        shift
        ;;
      --database)
        [[ $# -ge 2 ]] || die 'Option --database requires a value.'
        DATABASES+=("$2")
        shift
        ;;
      --label)
        [[ $# -ge 2 ]] || die 'Option --label requires a value.'
        LABEL="$2"
        shift
        ;;
      --skip-k3s)
        INCLUDE_K3S=false
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

  [[ -n "${OUTPUT_DIRECTORY}" ]] \
    || { usage >&2; die 'Option --output-dir is required.'; }

  require_root
  require_command sqlite3
  require_command sha256sum
  require_command su

  refuse_git_working_tree "${OUTPUT_DIRECTORY}"

  mkdir -p -- "${OUTPUT_DIRECTORY}"
  chmod 0700 "${OUTPUT_DIRECTORY}"
  OUTPUT_DIRECTORY="$(cd -- "${OUTPUT_DIRECTORY}" && pwd)"

  BACKUP_DIRECTORY="${OUTPUT_DIRECTORY}/$(date --utc +%Y%m%dT%H%M%SZ)"
  mkdir -p -- "${BACKUP_DIRECTORY}"
  chmod 0700 "${BACKUP_DIRECTORY}"

  (( ${#DATABASES[@]} > 0 )) || discover_databases

  local database
  for database in "${DATABASES[@]}"; do
    dump_database "${database}"
  done

  if [[ "${INCLUDE_K3S}" == "true" ]]; then
    backup_k3s_datastore
  else
    log 'Skipping the k3s datastore by request.'
  fi

  copy_platform_environment
  write_manifest

  log "Backup complete: ${BACKUP_DIRECTORY}"
  log "  total $(du -sh "${BACKUP_DIRECTORY}" | awk '{print $1}')"

  # A backup on the same disk protects against a bad migration and against nothing else.
  # The only failure mode this single-node platform actually has is losing the node.
  warn 'This copy is on the same disk it protects. Replicate it off the node, or it does not survive the failure it exists for.'
}

main "$@"
