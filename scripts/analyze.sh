#!/usr/bin/env bash
# SwiftLint's compiler-backed analyzer: `unused_declaration` over the app and
# the TankbookCore package it compiles in. A declaration nothing reads is a
# test that protects nothing or a behaviour the app does not have, and the
# compiler cannot say so on its own.
#
#   scripts/analyze.sh                  # fail on any finding not in the baseline
#   scripts/analyze.sh --write-baseline # record today's findings (after a triage)
#
# The baseline (.swiftlint-analyzer-baseline.json) holds findings that are not
# dead: declarations only the package tests, the app tests or `pump-read` use
# (this build does not compile them), and the analyzer's known blind spots - a
# property wrapper read only through `$`, an AVFoundation delegate method,
# SwiftUI's `@UIApplicationDelegateAdaptor`. A new unused declaration fails.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

log_dir="${ANALYZE_DIR:-${TMPDIR:-/tmp}/tankbook-analyze}"
mkdir -p "$log_dir"
log="$log_dir/build.log"
xcodegen generate >/dev/null || exit 1
xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$log_dir/dd" \
    CODE_SIGNING_ALLOWED=NO clean build > "$log" 2>&1
status=$?
if [ $status -ne 0 ]; then
    echo "[analyze] build failed ($status) - see $log" >&2
    exit $status
fi

baseline=.swiftlint-analyzer-baseline.json
if [ "${1:-}" = "--write-baseline" ]; then
    swiftlint analyze --compiler-log-path "$log" --only-rule unused_declaration --quiet \
        --write-baseline "$baseline"
    echo "[analyze] baseline written: $baseline"
    exit 0
fi
swiftlint analyze --compiler-log-path "$log" --only-rule unused_declaration --strict \
    --baseline "$baseline"
status=$?
echo "[analyze] exit $status"
exit $status
