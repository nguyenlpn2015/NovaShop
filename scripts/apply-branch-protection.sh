#!/usr/bin/env bash

# Applies the reviewed repository rulesets stored in .github/rulesets.
#
# Branch protection is the control that turns the documented delivery contract
# into an enforced one. Without it, CODEOWNERS is advisory and a direct push to
# the default branch bypasses every validation gate. Keeping the rulesets in Git
# means the protection itself is reviewable, diffable, and reproducible instead
# of being clicked into a settings page.
#
# The script defaults to a dry run and refuses to apply a ruleset whose required
# status checks have never been reported by an actual workflow run. A required
# check that no workflow produces would block every pull request permanently, so
# that mistake is caught before it is applied rather than afterwards.

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT
readonly CHECK_DISCOVERY_LIMIT="${CHECK_DISCOVERY_LIMIT:-20}"

REPOSITORY=""
RULESET_FILE=""
APPLY=false
SKIP_CHECK_VERIFICATION=false

log() {
  printf '[branch-protection] %s\n' "$*"
}

warn() {
  printf '[branch-protection] WARN: %s\n' "$*" >&2
}

die() {
  printf '[branch-protection] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

usage() {
  cat <<'EOF'
Usage: apply-branch-protection.sh --repo OWNER/REPO --ruleset FILE [--apply]

  --repo OWNER/REPO   Target repository.
  --ruleset FILE      Ruleset definition from .github/rulesets.
  --apply             Write the ruleset. Without this flag the script only
                      reports what it would do.
  --skip-check-verification
                      Apply even when a required status check has never been
                      reported. Use only for a first-time bootstrap where the
                      workflows have not run yet.

Requires the GitHub CLI with administration:write on the target repository.
EOF
}

# Collects check-run names GitHub has actually reported. This is the ground
# truth for required status check contexts, which cannot be guessed reliably
# because reusable workflows report as "<caller job> / <called job>".
#
# Both recent default-branch commits and recent pull request head commits are
# inspected. A repository whose validation workflow triggers only on
# pull_request never produces a check run on the default branch, because a
# squash merge creates a commit the workflow never sees. Looking only at the
# default branch would report such contexts as nonexistent and refuse to apply
# a ruleset that is correct.
discover_reported_checks() {
  local default_branch
  local commit_sha

  default_branch="$(
    gh api "repos/${REPOSITORY}" --jq '.default_branch'
  )"

  {
    gh api \
      "repos/${REPOSITORY}/commits?sha=${default_branch}&per_page=${CHECK_DISCOVERY_LIMIT}" \
      --jq '.[].sha' 2>/dev/null || true
    gh api \
      "repos/${REPOSITORY}/pulls?state=all&sort=updated&direction=desc&per_page=${CHECK_DISCOVERY_LIMIT}" \
      --jq '.[].head.sha' 2>/dev/null || true
  } | tr -d '\r' | sort --unique | while IFS= read -r commit_sha; do
    [[ -n "${commit_sha}" ]] || continue
    gh api \
      "repos/${REPOSITORY}/commits/${commit_sha}/check-runs?per_page=100" \
      --jq '.check_runs[].name' 2>/dev/null || true
  done | tr -d '\r' | sort --unique
}

verify_required_checks() {
  local reported
  local required
  local context
  local missing=0

  # Both lists are stripped of carriage returns before comparison. A Windows
  # build of jq terminates lines with CRLF while `gh api --jq` emits LF, so an
  # unstripped comparison reports every context as never reported and refuses
  # to apply a ruleset that is in fact correct.
  required="$(
    jq -r '
      .rules[]
      | select(.type == "required_status_checks")
      | .parameters.required_status_checks[].context
    ' "${RULESET_FILE}" | tr -d '\r'
  )"

  if [[ -z "${required}" ]]; then
    log 'Ruleset declares no required status checks.'
    return
  fi

  reported="$(discover_reported_checks)"
  if [[ -z "${reported}" ]]; then
    warn 'No check run has been reported on the default branch yet.'
    [[ "${SKIP_CHECK_VERIFICATION}" == "true" ]] \
      || die 'Refusing to apply required checks that have never run. Merge the workflows first, or pass --skip-check-verification.'
    return
  fi

  log 'Check runs observed on recent default-branch and pull request commits:'
  printf '%s\n' "${reported}" | sed 's/^/[branch-protection]   /'

  while IFS= read -r context; do
    [[ -n "${context}" ]] || continue
    if grep --fixed-strings --line-regexp --quiet "${context}" \
      <<<"${reported}"; then
      log "required check is reported: ${context}"
    else
      warn "required check has never been reported: ${context}"
      missing=$((missing + 1))
    fi
  done <<<"${required}"

  if (( missing > 0 )); then
    [[ "${SKIP_CHECK_VERIFICATION}" == "true" ]] \
      || die "${missing} required check(s) would never be satisfied. Fix the ruleset or the workflow job names."
    warn "Applying with ${missing} unverified check(s) on request."
  fi
}

existing_ruleset_id() {
  local name

  name="$(jq -r '.name' "${RULESET_FILE}")"
  gh api "repos/${REPOSITORY}/rulesets?per_page=100" \
    --jq "map(select(.name == \"${name}\")) | .[0].id // empty"
}

apply_ruleset() {
  local ruleset_id

  ruleset_id="$(existing_ruleset_id)"

  if [[ "${APPLY}" != "true" ]]; then
    if [[ -n "${ruleset_id}" ]]; then
      log "Dry run: would update ruleset ${ruleset_id} on ${REPOSITORY}."
    else
      log "Dry run: would create a new ruleset on ${REPOSITORY}."
    fi
    log 'Rerun with --apply to write the change.'
    return
  fi

  if [[ -n "${ruleset_id}" ]]; then
    log "Updating ruleset ${ruleset_id} on ${REPOSITORY}."
    gh api --method PUT \
      "repos/${REPOSITORY}/rulesets/${ruleset_id}" \
      --input "${RULESET_FILE}" >/dev/null
  else
    log "Creating ruleset on ${REPOSITORY}."
    gh api --method POST \
      "repos/${REPOSITORY}/rulesets" \
      --input "${RULESET_FILE}" >/dev/null
  fi

  log 'Applied. Current rulesets:'
  gh api "repos/${REPOSITORY}/rulesets" \
    --jq '.[] | "  \(.id)  \(.name)  \(.enforcement)"'
}

main() {
  while (( $# > 0 )); do
    case "$1" in
      --repo)
        [[ $# -ge 2 ]] || die 'Option --repo requires a value.'
        REPOSITORY="$2"
        shift
        ;;
      --ruleset)
        [[ $# -ge 2 ]] || die 'Option --ruleset requires a value.'
        RULESET_FILE="$2"
        shift
        ;;
      --apply)
        APPLY=true
        ;;
      --skip-check-verification)
        SKIP_CHECK_VERIFICATION=true
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

  require_command gh
  require_command jq

  [[ -n "${REPOSITORY}" ]] || { usage >&2; die 'Option --repo is required.'; }
  [[ -n "${RULESET_FILE}" ]] || { usage >&2; die 'Option --ruleset is required.'; }
  [[ -r "${RULESET_FILE}" ]] || die "Ruleset file is not readable: ${RULESET_FILE}"
  jq empty "${RULESET_FILE}" 2>/dev/null \
    || die "Ruleset file is not valid JSON: ${RULESET_FILE}"

  gh auth status >/dev/null 2>&1 \
    || die 'GitHub CLI is not authenticated. Run: gh auth login'

  log "Repository: ${REPOSITORY}"
  log "Ruleset: ${RULESET_FILE}"

  verify_required_checks
  apply_ruleset
}

main "$@"
