#!/usr/bin/env bash
# Tankbook release build: archive -> export -> (optionally) upload to App Store Connect.
# docs/STORE.md -> "Release checklist", SH.2 in docs/TASKS.md.
#
# Usage:
#   TANKBOOK_TEAM_ID=ABCDE12345 scripts/release.sh            # archive + export only
#   TANKBOOK_TEAM_ID=... ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=~/.private_keys/AuthKey_XXXX.p8 \
#       scripts/release.sh --upload                            # ...and upload
#
# Every step is judged by exit code. Nothing here is a secret: the team id is an
# identity, and the API key stays outside the repo - ASC_KEY_PATH is validated,
# never copied and never printed. The .p8 downloads ONCE from App Store Connect
# and cannot be retrieved again; losing it means revoking and re-issuing.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TANKBOOK_TEAM_ID:?set TANKBOOK_TEAM_ID to the Apple Developer team id (docs/STORE.md)}"
UPLOAD=0
case "${1:-}" in
  "")        ;;
  --upload)  UPLOAD=1 ;;
  *) echo "release: unknown argument '${1}'. The only flag is --upload;" >&2
     echo "  -allowProvisioningUpdates is already passed to xcodebuild internally." >&2
     exit 2 ;;
esac

validate_upload_credentials() {
: "${ASC_KEY_ID:?set ASC_KEY_ID to the App Store Connect API key id}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID to the App Store Connect issuer id}"
: "${ASC_KEY_PATH:?set ASC_KEY_PATH to the downloaded AuthKey_<KEYID>.p8}"

# altool --apiKey does NOT take a path: it searches a fixed set of
# directories for AuthKey_<id>.p8. So ASC_KEY_PATH cannot be passed through -
# it is validated instead. Before this check the variable was REQUIRED and
# then ignored, so a key stored anywhere else passed here and failed inside
# altool with "could not find the API key", which points at the key rather
# than at its location.
[ -f "$ASC_KEY_PATH" ] || { echo "release: no such key file: ${ASC_KEY_PATH}" >&2; exit 2; }
case "$(basename "$ASC_KEY_PATH")" in
  "AuthKey_${ASC_KEY_ID}.p8") ;;
  *) echo "release: ${ASC_KEY_PATH} must be named AuthKey_${ASC_KEY_ID}.p8 - altool locates the key by that exact filename" >&2; exit 2 ;;
esac
key_dir="$(cd "$(dirname "$ASC_KEY_PATH")" && pwd)"
case "$key_dir" in
  "$PWD/private_keys"|"$HOME/private_keys"|"$HOME/.private_keys"|"$HOME/.appstoreconnect/private_keys") ;;
  *) echo "release: altool only searches ./private_keys, ~/private_keys, ~/.private_keys and ~/.appstoreconnect/private_keys." >&2
     echo "  Move the key there:  mkdir -p ~/.private_keys && mv '${ASC_KEY_PATH}' ~/.private_keys/" >&2
     exit 2 ;;
esac
}

# Checked BEFORE the archive when uploading. The archive and export take
# minutes; discovering a missing key afterwards wastes all of it and leaves an
# IPA that looks like a failed release. Same ordering rule as the deploy
# script: everything that can be checked cheaply happens before the expensive,
# hard-to-undo step.
[ "$UPLOAD" -eq 1 ] && validate_upload_credentials

# Build number: the commit count on the archived commit - monotonic on main, and
# App Store Connect rejects a reused number. The marketing version stays in project.yml.
BUILD_NUMBER="$(git rev-list --count HEAD)"
COMMIT="$(git rev-parse --short HEAD)"
# `git status --porcelain` skips IGNORED files, and build/ is ignored - otherwise
# this script's own output (build/release-<n>-<sha>/) would make the tree dirty
# and refuse the NEXT run, which is what happened after build 463.
if [ -n "$(git status --porcelain)" ]; then
  echo "release: the tree is dirty - archive a committed state so the build number means something" >&2
  git status --short >&2
  exit 2
fi

OUT="build/release-${BUILD_NUMBER}-${COMMIT}"; mkdir -p "$OUT"
echo "release: build ${BUILD_NUMBER} from ${COMMIT} -> ${OUT}"

xcodegen generate >/dev/null
xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "${OUT}/Tankbook.xcarchive" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
  archive | tail -3
echo "ARCHIVE_EXIT=${PIPESTATUS[0]}"; [ "${PIPESTATUS[0]}" -eq 0 ] || exit 1

xcodebuild -exportArchive \
  -archivePath "${OUT}/Tankbook.xcarchive" \
  -exportOptionsPlist ios/App/ExportOptions.plist \
  -exportPath "${OUT}/export" \
  -allowProvisioningUpdates | tail -3
echo "EXPORT_EXIT=${PIPESTATUS[0]}"; [ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
IPA="$(ls "${OUT}"/export/*.ipa | head -1)"; echo "release: ${IPA} ($(du -h "${IPA}" | cut -f1))"

# The dSYM is the ONLY production crash signal (project.yml note); keep it with the build.
ls "${OUT}/Tankbook.xcarchive/dSYMs" >/dev/null

if [ "$UPLOAD" -eq 1 ]; then
  upload_log="${OUT}/altool.log"
  set +e
  xcrun altool --upload-app --type ios --file "${IPA}" \
    --apiKey "${ASC_KEY_ID}" --apiIssuer "${ASC_ISSUER_ID}" > "$upload_log" 2>&1
  upload_exit=$?
  set -e
  tail -3 "$upload_log"
  echo "UPLOAD_EXIT=${upload_exit}"

  if [ "$upload_exit" -ne 0 ]; then
    # altool's failures are accurate and unreadable. Translating the ones that
    # actually happen is the same rule the app follows for users: an error names
    # its next step (hard rule 7 applies to operators too).
    if grep -q "Cannot determine the Apple ID from Bundle ID" "$upload_log"; then
      echo "release: there is no App Store Connect APP RECORD for this bundle id yet." >&2
      echo "  Registering the App ID in Certificates, IDs & Profiles is a DIFFERENT step." >&2
      echo "  App Store Connect -> Apps -> + -> New App, bundle id app.tankbook.Tankbook," >&2
      echo "  then re-run. The archive at ${IPA} is fine and can be uploaded as-is." >&2
    elif grep -qi "Authentication credentials are missing or invalid\|401" "$upload_log"; then
      echo "release: the API key was rejected. Check ASC_ISSUER_ID (it is the UUID ABOVE the" >&2
      echo "  keys table, not in the key's row) and that the key still has App Manager access." >&2
    elif grep -qi "redundant binary\|already exists" "$upload_log"; then
      echo "release: build ${BUILD_NUMBER} was already uploaded. The build number is the commit" >&2
      echo "  count, so commit something (or re-archive a later commit) before re-uploading." >&2
    fi
    echo "  full log: ${upload_log}" >&2
    exit 1
  fi
  echo "release: uploaded build ${BUILD_NUMBER}; internal TestFlight testers get it after processing"
else
  echo "release: not uploaded (pass --upload with the App Store Connect API key in the environment)"
fi
