#!/usr/bin/env bash
# The baseline gate for iOS work (RV.174).
#
# `swift build` and `swift test` compile the SwiftPM package
# (ios/Sources/TankbookCore) only. Every screen lives in the app target
# (ios/App/Sources), which only `xcodebuild` compiles - so package-green is NOT
# app-green, and a gate that stops after `swift test` can pass code that does
# not compile into the app. This runs the package build, the lint, the
# app-target build and the package tests in order and stops at the first
# non-zero step.
#
# Usage:
#   scripts/gate.sh              # Debug app build
#   RELEASE=1 scripts/gate.sh    # also builds the app in Release
#
# Exit status is the first failing step's status, 0 when every step passes.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

destination='generic/platform=iOS Simulator'
release="${RELEASE:-0}"

# run <label> <directory> <command...>
run() {
  local label="$1" dir="$2"
  shift 2
  local code=0
  ( cd "$dir" && "$@" ) || code=$?
  printf '[gate] %-7s exit %-3s %s\n' "$label" "$code" "$*"
  return "$code"
}

run package ios swift build || exit $?
run lint    .   swiftlint lint || exit $?
run app     .   xcodegen generate || exit $?
run app     .   xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
  -configuration Debug -destination "$destination" CODE_SIGNING_ALLOWED=NO build || exit $?
if [ "$release" = "1" ]; then
  run release . xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
    -configuration Release -destination "$destination" CODE_SIGNING_ALLOWED=NO build || exit $?
fi
run tests   ios swift test || exit $?

echo '[gate] all steps passed'
