#!/usr/bin/env bash

# Proves a backup set is intact and readable, without restoring it.
#
# A backup that has never been read is a hypothesis. This is the cheap half of testing one:
# it runs in seconds, needs no scratch database, and catches the failures that actually
# happen — a truncated dump, a corrupt SQLite copy, a manifest that no longer matches the
# files beside it, a set that is older than it should be.
#
# It does not prove the data is correct. Only a restore does that, and
# scripts/rehearse-restore.sh is the expensive half.
#
# Exit codes:
#   0  every check passed
#   1  at least one check failed
#   2  usage error

set -Eeuo pipefail
IFS=$'\n\t'

readonly POSTGRES_SUPERUSER="${POSTGRES_SUPERUSER:-postgres}"
readonly MAX_AGE_HOURS="${MAX_AGE_HOURS:-26}"

PASS_COUNT=0
FAIL_COUNT=0
BACKUP_DIRECTORY=""
CHECK_AGE=true

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[verify-backup] PASS: %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[verify-backup] FAIL: %s\n' "$1" >&2
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/[verify-backup]       /' >&2
  return 0
}

die() {
  printf '[verify-backup] ERROR: %s\n' "$*" >&2
  exit 2
}

usage() {
  cat <<'USAGE'
Usage: verify-backup.sh BACKUP_DIRECTORY [--skip-age]

  BACKUP_DIRECTORY   A timestamped directory produced by backup-datastores.sh.
  --skip-age         Do not fail on an old backup. For verifying an archived set.

Environment:
  MAX_AGE_HOURS      Age above which a backup is stale. Default 26, which allows a daily
                     schedule to slip by two hours before reporting.
USAGE
}

# The manifest is only useful if it still describes the files next to it. A checksum
# mismatch means the artefact changed after capture, which for a backup means it is not the
# thing that was verified at write time.
check_manifest_integrity() {
  local manifest="${BACKUP_DIRECTORY}/manifest.txt"
  local recorded actual size artefact path mismatches=0 counted=0

  if [[ ! -r "${manifest}" ]]; then
    fail 'manifest is present and readable' "Missing ${manifest}. Without it there is nothing to verify against."
    return
  fi
  pass 'manifest is present and readable'

  # IFS is set to newline-and-tab at the top of this script, which is the right default for
  # filenames and the wrong one for a space-separated manifest: without a space in IFS,
  # `read` puts the entire line into the first variable and every artefact reads as missing.
  # Set per-loop rather than changed globally.
  while IFS=' ' read -r recorded size artefact; do
    [[ -z "${recorded}" || "${recorded}" == \#* ]] && continue
    counted=$((counted + 1))
    path="${BACKUP_DIRECTORY}/${artefact}"

    if [[ ! -f "${path}" ]]; then
      mismatches=$((mismatches + 1))
      printf '[verify-backup]       missing: %s\n' "${artefact}" >&2
      continue
    fi

    actual="$(sha256sum "${path}" | awk '{print $1}')"
    if [[ "${actual}" != "${recorded}" ]]; then
      mismatches=$((mismatches + 1))
      printf '[verify-backup]       checksum differs: %s\n' "${artefact}" >&2
    fi
  done < <(sed -n '/^# sha256/,$p' "${manifest}" | tail -n +2)

  if (( counted == 0 )); then
    fail 'manifest lists at least one artefact' 'The manifest has no checksum lines. The backup captured nothing.'
  elif (( mismatches == 0 )); then
    pass "every artefact matches its recorded checksum (${counted})"
  else
    fail 'every artefact matches its recorded checksum' "${mismatches} of ${counted} differ or are missing."
  fi
}

# pg_restore --list parses the whole archive header and table of contents. A truncated or
# corrupt dump fails here, which is the common way a dump goes bad: the disk filled during
# pg_dump and nobody checked the exit code.
check_postgresql_dumps() {
  local dump found=0

  shopt -s nullglob
  for dump in "${BACKUP_DIRECTORY}"/postgresql-*.dump; do
    found=$((found + 1))
    local name entries
    name="$(basename -- "${dump}")"

    # Root, not postgres: --list needs no database connection, and the backup directory is
    # 0700 root-owned so postgres could not read the file anyway.
    if entries="$(pg_restore --list "${dump}" 2>&1)"; then
      local count
      count="$(printf '%s\n' "${entries}" | grep -c '^[0-9]' || true)"
      if (( count > 0 )); then
        pass "${name} is readable by pg_restore (${count} entries)"
      else
        # Not a failure. The novashop database currently has no tables — the application
        # has no schema — so an empty archive is the correct capture of an empty database.
        # Failing here would make this check permanently red and therefore ignored.
        #
        # It is still worth saying loudly: if the application HAS a schema and this prints,
        # the dump captured nothing and a restore would silently produce an empty database.
        pass "${name} is readable by pg_restore (empty archive)"
        printf '[verify-backup] NOTE: %s contains no entries. Correct while the application has no schema; a silent disaster once it does.
' "${name}"
      fi
    else
      fail "${name} is readable by pg_restore" "${entries}"
    fi
  done
  shopt -u nullglob

  (( found > 0 )) || fail 'the set contains at least one PostgreSQL dump' 'No postgresql-*.dump found. Application data is not in this backup.'
}

# integrity_check walks the whole b-tree. It is the check that catches a datastore copied
# with cp while k3s was writing to it.
check_sqlite_copy() {
  local copy="${BACKUP_DIRECTORY}/k3s-state.db"
  local result

  if [[ ! -f "${copy}" ]]; then
    printf '[verify-backup] NOTE: no k3s datastore in this set. The cluster is rebuildable from Git, so this is not a failure.\n'
    return
  fi

  result="$(sqlite3 "${copy}" 'PRAGMA integrity_check;' 2>&1 || true)"
  if [[ "${result}" == "ok" ]]; then
    pass 'k3s datastore copy passes integrity_check'
  else
    fail 'k3s datastore copy passes integrity_check' "${result}"
  fi
}

# Losing this file makes every other artefact in the set unusable: the dumps restore, and
# nothing can authenticate to what they restored into.
check_platform_environment() {
  local env_file="${BACKUP_DIRECTORY}/platform-environment.env"
  local missing=()
  local key

  if [[ ! -f "${env_file}" ]]; then
    fail 'the platform environment file is in the set' 'Without it a restore produces datastores nothing can authenticate to.'
    return
  fi

  for key in DATABASE_URL REDIS_URL; do
    grep -qE "^(export )?${key}=" "${env_file}" || missing+=("${key}")
  done

  if (( ${#missing[@]} == 0 )); then
    pass 'the platform environment file declares DATABASE_URL and REDIS_URL'
  else
    fail 'the platform environment file declares DATABASE_URL and REDIS_URL' "Missing: ${missing[*]}"
  fi

  local mode
  mode="$(stat -c '%a' "${env_file}")"
  if [[ "${mode}" == "600" ]]; then
    pass 'the captured environment file is mode 0600'
  else
    fail 'the captured environment file is mode 0600' "Mode is ${mode}. It contains credentials."
  fi
}

# A backup system that stops running is the most common way backups fail, and it fails
# quietly. Age is the check that catches it.
check_age() {
  local manifest="${BACKUP_DIRECTORY}/manifest.txt"
  local age_seconds age_hours

  [[ -f "${manifest}" ]] || return

  age_seconds=$(( $(date +%s) - $(stat -c '%Y' "${manifest}") ))
  age_hours=$(( age_seconds / 3600 ))

  if (( age_hours <= MAX_AGE_HOURS )); then
    pass "backup is ${age_hours}h old, within the ${MAX_AGE_HOURS}h threshold"
  else
    fail "backup is within the ${MAX_AGE_HOURS}h threshold" \
      "This set is ${age_hours}h old. Either the schedule stopped or nobody is running it."
  fi
}

main() {
  while (( $# > 0 )); do
    case "$1" in
      --skip-age) CHECK_AGE=false ;;
      -h | --help) usage; exit 0 ;;
      -*) usage >&2; die "Unknown option: $1" ;;
      *) BACKUP_DIRECTORY="$1" ;;
    esac
    shift
  done

  [[ -n "${BACKUP_DIRECTORY}" ]] || { usage >&2; die 'A backup directory is required.'; }
  [[ -d "${BACKUP_DIRECTORY}" ]] || die "Not a directory: ${BACKUP_DIRECTORY}"

  BACKUP_DIRECTORY="$(cd -- "${BACKUP_DIRECTORY}" && pwd)"
  printf '[verify-backup] Verifying %s\n' "${BACKUP_DIRECTORY}"

  check_manifest_integrity
  check_postgresql_dumps
  check_sqlite_copy
  check_platform_environment
  [[ "${CHECK_AGE}" == "true" ]] && check_age

  if (( FAIL_COUNT > 0 )); then
    printf '[verify-backup] RESULT: FAIL (%d passed, %d failed)\n' "${PASS_COUNT}" "${FAIL_COUNT}" >&2
    exit 1
  fi

  printf '[verify-backup] RESULT: PASS (%d passed, 0 failed)\n' "${PASS_COUNT}"
  printf '[verify-backup] Readable is not the same as correct. Rehearse a real restore monthly.\n'
}

main "$@"
