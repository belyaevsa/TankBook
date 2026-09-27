#!/usr/bin/env bash
# Fetch one debug case straight from Object Storage with the owner's `yc` CLI,
# for when the admin viewer (scripts/case.sh) is not reachable. The parts live
# at tankbook-blobs/<owner>/cases/<id>/<part> (CaseKeys.PartKey); the owner
# (account or device id) is not known from the case id, so every owner prefix
# is searched for the case folder.
#
#   scripts/case-yc.sh 02412-PM1N2
#
# A case holds user content, so it lands outside the repo, in
# ~/.cache/tankbook/cases/<id>/ (TANKBOOK_CASES_DIR overrides the parent).
# This path writes no access-log row - the viewer's log only covers its own reads.
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: scripts/case-yc.sh <case-id>" >&2; exit 2; }
BUCKET="${TANKBOOK_BLOBS_BUCKET:-tankbook-blobs}"

COMPACT="$(printf '%s' "$1" | tr -d '-' | tr '[:lower:]' '[:upper:]')"
if ! printf '%s' "$COMPACT" | grep -Eq '^[0-9A-HJKMNP-TV-Z]{10}$'; then
  echo "case: '$1' is not a case id (ten characters, like K7Q2M-9XDRA)" >&2
  exit 1
fi
CASE_ID="${COMPACT:0:5}-${COMPACT:5:5}"

command -v yc >/dev/null || { echo "case: yc is not on PATH" >&2; exit 1; }
command -v jq >/dev/null || { echo "case: jq is not on PATH" >&2; exit 1; }

list() { yc storage s3api list-objects --bucket "$BUCKET" --format json "$@"; }

# Owner prefixes, following continuation tokens past 1000.
owners=()
token=""
while :; do
  page="$(list --delimiter / ${token:+--continuation-token "$token"})"
  while IFS= read -r p; do [ -n "$p" ] && owners+=("$p"); done \
    < <(printf '%s' "$page" | jq -r '.common_prefixes[]?.prefix')
  token="$(printf '%s' "$page" | jq -r '.next_continuation_token // empty')"
  [ -n "$token" ] || break
done

PREFIX=""
for owner in "${owners[@]}"; do
  if list --prefix "${owner}cases/${CASE_ID}/" --max-keys 1 | jq -e '(.contents // []) | length > 0' >/dev/null; then
    PREFIX="${owner}cases/${CASE_ID}/"
    break
  fi
done
if [ -z "$PREFIX" ]; then
  echo "case: ${CASE_ID} is not in ${BUCKET} - still in the API's upload spool, purged (30 days), or a mistyped id" >&2
  exit 1
fi

OUT="${TANKBOOK_CASES_DIR:-${HOME}/.cache/tankbook/cases}/${CASE_ID}"
mkdir -p "$OUT"
while IFS= read -r key; do
  yc storage s3 cp "s3://${BUCKET}/${key}" "${OUT}/${key##*/}" >/dev/null
  echo "  ${key##*/}"
done < <(list --prefix "$PREFIX" | jq -r '.contents[].key')
echo "case: ${CASE_ID} (owner ${PREFIX%%/*}) -> ${OUT}"
