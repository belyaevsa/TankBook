#!/usr/bin/env bash
# Fetch one debug case straight from Azure Blob Storage with the owner's `az`
# CLI, for when the admin viewer (scripts/case.sh) is not reachable. The parts
# live at tankbook-blobs/<owner>/cases/<id>/<part> (CaseKeys.PartKey) in the
# `tankbookstorage` account; the owner (account or device id) is not known from
# the case id, so the container listing is searched for the case folder.
#
#   scripts/case-az.sh 02412-PM1N2
#
# Auth is the owner's `az login`: by default the CLI fetches the account key
# through it (AZURE_STORAGE_AUTH_MODE=key); set AZURE_STORAGE_AUTH_MODE=login to
# read with the Storage Blob Data Reader/Contributor role instead.
#
# A case holds user content, so it lands outside the repo, in
# ~/.cache/tankbook/cases/<id>/ (TANKBOOK_CASES_DIR overrides the parent).
# This path writes no access-log row - the viewer's log only covers its own reads.
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: scripts/case-az.sh <case-id>" >&2; exit 2; }
ACCOUNT="${TANKBOOK_BLOBS_ACCOUNT:-tankbookstorage}"
CONTAINER="${TANKBOOK_BLOBS_CONTAINER:-tankbook-blobs}"
export AZURE_STORAGE_AUTH_MODE="${AZURE_STORAGE_AUTH_MODE:-key}"

COMPACT="$(printf '%s' "$1" | tr -d '-' | tr '[:lower:]' '[:upper:]')"
if ! printf '%s' "$COMPACT" | grep -Eq '^[0-9A-HJKMNP-TV-Z]{10}$'; then
  echo "case: '$1' is not a case id (ten characters, like K7Q2M-9XDRA)" >&2
  exit 1
fi
CASE_ID="${COMPACT:0:5}-${COMPACT:5:5}"

command -v az >/dev/null || { echo "case: az is not on PATH" >&2; exit 1; }

# One listing of the whole container's key names (synced attachments
# included - names only, no content), filtered by the CLI to this case's folder.
keys=()
while IFS= read -r k; do [ -n "$k" ] && keys+=("$k"); done < <(
  az storage blob list --account-name "$ACCOUNT" -c "$CONTAINER" --num-results '*' --only-show-errors \
    --query "[?contains(name, '/cases/${CASE_ID}/')].name" -o tsv)
if [ ${#keys[@]} -eq 0 ]; then
  echo "case: ${CASE_ID} is not in ${ACCOUNT}/${CONTAINER} - still in the API's upload spool, purged (30 days), a mistyped id, or (until the backend writes to Azure) only in Yandex: scripts/case-yc.sh" >&2
  exit 1
fi

OUT="${TANKBOOK_CASES_DIR:-${HOME}/.cache/tankbook/cases}/${CASE_ID}"
mkdir -p "$OUT"
for key in "${keys[@]}"; do
  az storage blob download --account-name "$ACCOUNT" -c "$CONTAINER" -n "$key" -f "${OUT}/${key##*/}" \
    --overwrite --no-progress --only-show-errors -o none
  echo "  ${key##*/}"
done
echo "case: ${CASE_ID} (owner ${keys[0]%%/*}) -> ${OUT}"
