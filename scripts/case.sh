#!/usr/bin/env bash
# Fetch one debug case by the id the phone showed (hard rule 9's debug-cases
# amendment, docs/SECURITY.md -> "The admin viewer"): the envelope, then every
# part - the log, the scan photos, their pipeline traces - into a folder on
# this Mac. The read key opens the case routes of the admin viewer and nothing
# else; every fetch writes an access-log row there.
#
#   scripts/case.sh K7Q2M-9XDRA            # production
#   scripts/case.sh K7Q2M-9XDRA --stage    # staging
#
# The key and the URLs live in ~/.config/tankbook/admin-read.env, never in the
# repo:
#   TANKBOOK_ADMIN_URL=https://admin.tankbook.live
#   TANKBOOK_ADMIN_URL_STAGE=https://admin.stage.tankbook.live
#   TANKBOOK_ADMIN_READ_KEY=...          # production
#   TANKBOOK_ADMIN_READ_KEY_STAGE=...    # staging
#
# A case holds user content, so it lands outside the repo, in
# ~/.cache/tankbook/cases/<id>/ (TANKBOOK_CASES_DIR overrides the parent).
set -euo pipefail

usage() { echo "usage: scripts/case.sh <case-id> [--stage]" >&2; exit 2; }
[ $# -ge 1 ] || usage
CASE_ID="$1"; shift
ENVIRONMENT=prod
for arg in "$@"; do
  case "$arg" in
    --stage) ENVIRONMENT=stage ;;
    *) usage ;;
  esac
done

CONFIG="${HOME}/.config/tankbook/admin-read.env"
if [ ! -f "$CONFIG" ]; then
  echo "case: ${CONFIG} is missing - it holds the admin URL and the read key (see the header of this script)" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG"

if [ "$ENVIRONMENT" = stage ]; then
  URL="${TANKBOOK_ADMIN_URL_STAGE:-}"; KEY="${TANKBOOK_ADMIN_READ_KEY_STAGE:-}"
else
  URL="${TANKBOOK_ADMIN_URL:-}"; KEY="${TANKBOOK_ADMIN_READ_KEY:-}"
fi
if [ -z "$URL" ] || [ -z "$KEY" ]; then
  echo "case: no ${ENVIRONMENT} URL or read key in ${CONFIG}" >&2
  exit 1
fi

# The id as the API stores it: upper case, the dash after five characters.
COMPACT="$(printf '%s' "$CASE_ID" | tr -d '-' | tr '[:lower:]' '[:upper:]')"
if ! printf '%s' "$COMPACT" | grep -Eq '^[0-9A-HJKMNP-TV-Z]{10}$'; then
  echo "case: '${CASE_ID}' is not a case id (ten characters, like K7Q2M-9XDRA)" >&2
  exit 1
fi
CASE_ID="${COMPACT:0:5}-${COMPACT:5:5}"

OUT="${TANKBOOK_CASES_DIR:-${HOME}/.cache/tankbook/cases}/${CASE_ID}"
mkdir -p "$OUT"
chmod 700 "$OUT"

fetch() { # <path> <output file>
  local status
  status="$(curl -sS -o "$2" -w '%{http_code}' -H "Authorization: Bearer ${KEY}" "${URL%/}$1")"
  case "$status" in
    200) return 0 ;;
    401) echo "case: the read key was refused (${ENVIRONMENT})" >&2 ;;
    404) echo "case: ${CASE_ID} not found on ${ENVIRONMENT} - wrong id, wrong server, or older than 30 days" >&2 ;;
    429) echo "case: rate-limited, try again in a minute" >&2 ;;
    *) echo "case: ${1} answered ${status}" >&2 ;;
  esac
  rm -f "$2"
  return 1
}

fetch "/api/cases/${CASE_ID}" "${OUT}/case.json"
jq -r '.parts[].name' "${OUT}/case.json" | while IFS= read -r name; do
  # Part names are the API's own `^[a-z0-9][a-z0-9._-]{0,63}$`, safe as file names.
  fetch "/api/cases/${CASE_ID}/parts/${name}" "${OUT}/${name}"
done

echo "case: ${CASE_ID} (${ENVIRONMENT}) -> ${OUT}"
jq -r '"  sent \(.createdAt) by \(.app // "unknown app"), \(.parts | length) parts, \(.totalBytes) bytes"' "${OUT}/case.json"
ls -1 "$OUT" | sed 's/^/  /'
