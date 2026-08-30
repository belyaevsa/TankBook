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
# identity, the API key stays outside the repo and is referenced by path.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TANKBOOK_TEAM_ID:?set TANKBOOK_TEAM_ID to the Apple Developer team id (docs/STORE.md)}"
UPLOAD=0; [ "${1:-}" = "--upload" ] && UPLOAD=1

# Build number: the commit count on the archived commit - monotonic on main, and
# App Store Connect rejects a reused number. The marketing version stays in project.yml.
BUILD_NUMBER="$(git rev-list --count HEAD)"
COMMIT="$(git rev-parse --short HEAD)"
if [ -n "$(git status --porcelain)" ]; then
  echo "release: the tree is dirty - archive a committed state so the build number means something" >&2; exit 2
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
  : "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_PATH:?}"
  xcrun altool --upload-app --type ios --file "${IPA}" \
    --apiKey "${ASC_KEY_ID}" --apiIssuer "${ASC_ISSUER_ID}" 2>&1 | tail -3
  echo "UPLOAD_EXIT=${PIPESTATUS[0]}"; [ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
  echo "release: uploaded build ${BUILD_NUMBER}; internal TestFlight testers get it after processing"
else
  echo "release: not uploaded (pass --upload with the App Store Connect API key in the environment)"
fi
