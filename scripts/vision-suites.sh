#!/usr/bin/env bash
# The OCR accuracy suites on their measured runtime: the iOS simulator
# (docs/TESTING.md -> "The OCR accuracy suites are runtime-specific").
#
# Vision reads the corpus differently on every OS, and the app runs on iOS, so
# the L5 marks - `high-water.json`, `PumpPhotoGate`'s measured counts, RV.56's
# zero confident-wrong totals, the screenshot cross-check and the expense dumps
# - are recorded and enforced in the iOS simulator. `swift test` on a Mac skips
# these suites with the reason printed; this runs the package's own test target
# in the simulator, only those suites, and prints each suite's result.
#
# Usage:
#   scripts/vision-suites.sh                       # every measured suite
#   scripts/vision-suites.sh RV56TotalPropertyTests # one suite
#   VISION_REWRITE_DUMPS=1 scripts/vision-suites.sh CorpusAccuracyGateTests
#                                                  # re-record the expense dumps here
#
# Exit status is xcodebuild's.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/ios" || exit 1

suites=("$@")
if [ ${#suites[@]} -eq 0 ]; then
    suites=(CorpusAccuracyGateTests CorpusCompressionTests CorpusPairTests RV56TotalPropertyTests
            ScreenshotCrossCheckTests)
fi
only=()
for suite in "${suites[@]}"; do only+=("-only-testing:TankbookCoreTests/$suite"); done

# The simulator's test process sees only variables xcodebuild forwards with the
# TEST_RUNNER_ prefix: every VISION_* and PUMP_* switch set here is forwarded
# (VISION_REWRITE_DUMPS=1, VISION_DUMP=<fixtures>, PUMP_ARMS=1, ...).
while IFS='=' read -r name _; do
    case "$name" in VISION_*|PUMP_*) export "TEST_RUNNER_$name=${!name}" ;; esac
done < <(env)

# One OCR at a time, as a phone reads one photo (TestOCR.serial).
export TEST_RUNNER_VISION_SERIAL=1

log="${VISION_SUITES_LOG:-/tmp/vision-suites.log}"
xcodebuild test -scheme TankbookCore-Package \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
    "${only[@]}" > "$log" 2>&1
status=$?
grep -E "^✘|^✔ Suite|Test run with|↳ " "$log" | grep -v "Testing Library Version\|Target Platform" | cut -c1-300
echo "[vision-suites] exit $status   (full log: $log)"
exit $status
