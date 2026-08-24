#!/usr/bin/env bash
# Re-capture every committed screenshot in design/screenshots/, EN and RU.
#
# Usage: scripts/capture-screenshots.sh [device]     (default: "iPhone 17")
#
# Why a script and not a manual pass: a shared change - the Home one-row header,
# a palette token, a font - invalidates screenshots across half a dozen tasks at
# once, and re-shooting them by hand is where the convention quietly dies. This
# reproduces the whole set from the current build in one go.
#
# Rules baked in, each learned the hard way (agents/briefs/README.md):
#   - Seeds are IDEMPOTENT and silently no-op on a populated database, so every
#     launch passes -homeResetDatabase. Without it you capture the previous
#     run's state - P1.6 shipped two screenshots of an "Entry not found" page.
#   - NEVER run this while `xcodebuild test` is running: they fight over the
#     device and both lose.
#   - Dark theme is the brand's home theme (docs/DESIGN.md), so that is what is
#     committed unless a task is specifically about light.
#
# The screenshots are the record of what shipped, and the ONLY check that
# catches colour, truncation and layout - XCUITest asserts behaviour, never how
# a screen looks. Open them after running; an agent cannot.

set -uo pipefail

DEVICE="${1:-iPhone 17}"
BUNDLE="app.tankbook.Tankbook"
OUT="design/screenshots"
APP="$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/Tankbook-*/Build/Products/Debug-iphonesimulator/Tankbook.app 2>/dev/null | head -1)"

if [ -z "${APP}" ] || [ ! -d "${APP}" ]; then
    echo "error: no built Tankbook.app found. Run:" >&2
    echo "  xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \\" >&2
    echo "    -destination 'platform=iOS Simulator,name=${DEVICE}' build" >&2
    exit 1
fi

if pgrep -f "xcodebuild.*test" >/dev/null 2>&1; then
    echo "error: a test run is in progress - it and simctl fight over the device." >&2
    exit 1
fi

echo "device: ${DEVICE}"
echo "app:    ${APP}"

xcrun simctl boot "${DEVICE}" 2>/dev/null
xcrun simctl bootstatus "${DEVICE}" -b >/dev/null 2>&1
xcrun simctl ui "${DEVICE}" appearance dark >/dev/null 2>&1
xcrun simctl install "${DEVICE}" "${APP}" || exit 1

# capture <output-name> <lang: en|ru> <launch args...>
capture() {
    local name="$1" lang="$2"; shift 2
    local path="${OUT}/${name}.png"
    xcrun simctl terminate "${DEVICE}" "${BUNDLE}" >/dev/null 2>&1
    if [ "${lang}" = "ru" ]; then
        xcrun simctl launch "${DEVICE}" "${BUNDLE}" \
            -AppleLanguages "(ru)" -AppleLocale ru_RU -homeResetDatabase "$@" >/dev/null 2>&1
    else
        xcrun simctl launch "${DEVICE}" "${BUNDLE}" -homeResetDatabase "$@" >/dev/null 2>&1
    fi
    sleep 6
    if xcrun simctl io "${DEVICE}" screenshot "${path}" >/dev/null 2>&1; then
        echo "  ok   ${path}"
    else
        echo "  FAIL ${path}" >&2
    fi
}

# Each task's screen, in task order. Both languages except where a task's
# screenshot is deliberately single-language (the light-theme shell, and the
# rejected accent-tab-bar record kept from P1.1).
capture P1.1-shell-dark            en -seedHomeFullHistory
capture P1.2-add-vehicle           en -presentScreen addVehicle
capture P1.2-add-vehicle-ru        ru -presentScreen addVehicle
capture P1.3-confirm-manual        en -seedVehicleForUITests -presentScreen confirmManual
capture P1.3-confirm-manual-ru     ru -seedVehicleForUITests -presentScreen confirmManual
capture P1.4-home                  en -seedHomeFullHistory
capture P1.4-home-ru               ru -seedHomeFullHistory
capture P1.4-home-empty            en -seedHomeEmptyVehicle
capture P1.4-home-empty-ru         ru -seedHomeEmptyVehicle
capture P1.5-log-stream            en -seedHomeFullHistory
capture P1.5-log-stream-ru         ru -seedHomeFullHistory
capture P1.6-edit-entry            en -seedEditEntry -presentScreen editEntry
capture P1.6-edit-entry-ru         ru -seedEditEntry -presentScreen editEntry
capture P1.7-recently-deleted      en -seedRecentlyDeleted -presentScreen recentlyDeleted
capture P1.7-recently-deleted-ru   ru -seedRecentlyDeleted -presentScreen recentlyDeleted
capture P1.8-duplicate-card        en -seedHomeDuplicate
capture P1.8-duplicate-card-ru     ru -seedHomeDuplicate
capture P1.9-tank-level            en -seedTankLevel -presentScreen tankLevel
capture P1.9-tank-level-ru         ru -seedTankLevel -presentScreen tankLevel
capture P1.10-trends               en -seedHomeFullHistory -selectTrendsTab
capture P1.10-trends-ru            ru -seedHomeFullHistory -selectTrendsTab
capture P1.10-trends-first-estimate en -seedHomeFirstEstimate -selectTrendsTab
capture P1.11-car-switcher         en -seedHomeCarSwitcher -presentScreen carSwitcher
capture P1.11-car-switcher-ru      ru -seedHomeCarSwitcher -presentScreen carSwitcher
capture P1.12-vehicle-detail       en -seedHomeCarSwitcher -presentScreen vehicleDetail
capture P1.12-vehicle-detail-ru    ru -seedHomeCarSwitcher -presentScreen vehicleDetail

# The light-theme shell is the one deliberate light capture (docs/DESIGN.md).
xcrun simctl ui "${DEVICE}" appearance light >/dev/null 2>&1
capture P1.1-shell-light en -seedHomeFullHistory
xcrun simctl ui "${DEVICE}" appearance dark >/dev/null 2>&1

echo
echo "Done. NOW OPEN THEM - this script proves a file was written, not that it"
echo "shows the intended screen. A wrong seed renders an empty or error state"
echo "that looks like a successful capture from here."
