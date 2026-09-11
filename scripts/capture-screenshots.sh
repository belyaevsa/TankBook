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

DEVICE="${1:-iPhone 17}"   # override: scripts/capture-screenshots.sh "iPhone 17 Pro"
BUNDLE="app.tankbook.Tankbook"
OUT="design/screenshots"
CAPTURED=()   # names this run actually wrote, for alias_shot
# Resolve the app THIS checkout built, by asking xcodebuild for its own build
# settings. The old `ls -dt DerivedData/Tankbook-*` picked the most RECENTLY
# BUILT app anywhere on the machine - which, with git worktrees, is routinely a
# different checkout's binary. You would then screenshot another branch's app
# and never know: the files are written, the script reports ok, and the images
# look plausible. Set APP=... to override.
if [ -z "${APP:-}" ]; then
    BUILT_DIR="$(xcodebuild -project Tankbook.xcodeproj -scheme Tankbook         -destination "platform=iOS Simulator,name=${DEVICE}"         -showBuildSettings 2>/dev/null         | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')"
    APP="${BUILT_DIR}/Tankbook.app"
fi

# Build before capturing, unless told not to (SKIP_BUILD=1). Resolving the
# built product is not the same as it being CURRENT: on 2026-08-25 a full
# 43-screenshot run was taken from a binary built before the change under
# review, reported "ok" for every file, and produced 43 confident images of the
# previous build. A stale capture is worse than no capture - it is evidence for
# the wrong code. Building here costs seconds when nothing changed.
if [ -z "${SKIP_BUILD:-}" ]; then
    echo "building ${DEVICE} (SKIP_BUILD=1 to skip)..."
    if ! xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
        -destination "platform=iOS Simulator,name=${DEVICE}" build >/dev/null 2>&1; then
        echo "error: build failed - capture would screenshot a stale binary. Run the build" >&2
        echo "  yourself to see why: xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \\" >&2
        echo "    -destination 'platform=iOS Simulator,name=${DEVICE}' build" >&2
        exit 1
    fi
fi

if [ -z "${APP}" ] || [ ! -d "${APP}" ]; then
    echo "error: no built Tankbook.app found. Run:" >&2
    echo "  xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \\" >&2
    echo "    -destination 'platform=iOS Simulator,name=${DEVICE}' build" >&2
    exit 1
fi

# Match the PROCESS NAME, never the command line. `pgrep -f "xcodebuild.*test"`
# matches any process whose ARGUMENTS contain those words - including an agent
# whose brief text mentions running xcodebuild, and including this script's own
# parent shell. On 2026-08-24 an agent copied that pattern, matched a sibling
# agent's opencode process, and killed it mid-task.
# The fight is over a DEVICE, not over the machine: with several worktrees
# running at once, another agent's xcodebuild on `iPhone 17 Pro` is no reason to
# refuse a capture on `iPhone 17`. So look at what the running xcodebuilds are
# actually driving, by reading the arguments of REAL pids from `pgrep -x` -
# never `pgrep -f`, which matches any process whose arguments merely mention
# xcodebuild (an agent's brief does, and `pkill -f` on that pattern killed a
# sibling agent mid-task on 2026-08-24).
busy_pids="$(pgrep -x xcodebuild 2>/dev/null || true)"
if [ -n "${busy_pids}" ]; then
    # Compare the device name EXACTLY. A substring test matches
    # "name=iPhone 17 Pro" against DEVICE="iPhone 17" and refuses a capture that
    # was never in conflict - the prefix collision that makes three of the four
    # simulator names overlap. Argv boundaries are lost in `ps -o args=`, so the
    # destination value is cut at the next xcodebuild verb.
    busy_devices="$(ps -o args= -p ${busy_pids} 2>/dev/null \
        | grep -o 'name=[^,]*' \
        | sed -E 's/^name=//; s/ (test|build|clean|archive|-.*)$//')"
    if printf '%s\n' "${busy_devices}" | grep -qx "${DEVICE}"; then
        echo "error: an xcodebuild is driving ${DEVICE} right now - it and simctl fight over it." >&2
        exit 1
    fi
    echo "note: xcodebuild is running on another device; continuing on ${DEVICE}."
fi

echo "device: ${DEVICE}"
echo "app:    ${APP}"

xcrun simctl boot "${DEVICE}" 2>/dev/null
xcrun simctl bootstatus "${DEVICE}" -b >/dev/null 2>&1
xcrun simctl ui "${DEVICE}" appearance dark >/dev/null 2>&1
xcrun simctl install "${DEVICE}" "${APP}" || exit 1

# The manifest (RV.176 + PR.28): every frame this run produces is recorded with
# the runtime, device and commit it came from, so a committed PNG is traceable
# to the environment that proved it. The runtime matters: a baseline captured on
# iOS 26.5 is not valid for iOS 18 (CLAUDE.md). Written per frame as it lands,
# then merged into design/screenshots/manifest.json at the end - merge, not
# rewrite, so a FILTERed run updates its own frames without discarding the rest.
MANIFEST="${OUT}/manifest.json"
MANIFEST_TSV="$(mktemp -t tankbook-manifest)"
# The runtime key is `com.apple.CoreSimulator.SimRuntime.iOS-26-5`; the trailing
# part is the value a human reads in the manifest.
RUNTIME="$(xcrun simctl list devices -j 2>/dev/null | python3 -c '
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)
for runtime, devices in data.get("devices", {}).items():
    for device in devices:
        if device.get("name") == name:
            print(runtime.split(".")[-1].replace("-", "."))
            sys.exit(0)
' "${DEVICE}")"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

# record_manifest <frame-name> - one TSV line, merged at the end of the run.
record_manifest() {
    printf '%s\t%s\t%s\t%s\n' "$1" "${RUNTIME}" "${DEVICE}" "${COMMIT}" >> "${MANIFEST_TSV}"
}

# capture <output-name> <lang: en|ru> <launch args...>
# FILTER="P1.4 P2.3" re-captures only the names that contain one of those words.
# Without it every screenshot is taken, which is the default because a shared
# change invalidates them across tasks at once.
capture() {
    local name="$1" lang="$2"; shift 2
    local path="${OUT}/${name}.png"
    if [ -n "${FILTER:-}" ]; then
        local wanted=1 pattern
        for pattern in ${FILTER}; do
            case "${name}" in *"${pattern}"*) wanted=0 ;; esac
        done
        [ "${wanted}" -eq 0 ] || return 0
    fi
    xcrun simctl terminate "${DEVICE}" "${BUNDLE}" >/dev/null 2>&1
    if [ "${lang}" = "ru" ]; then
        xcrun simctl launch "${DEVICE}" "${BUNDLE}" \
            -AppleLanguages "(ru)" -AppleLocale ru_RU -homeResetDatabase -freezeSyncState "$@" >/dev/null 2>&1
    else
        xcrun simctl launch "${DEVICE}" "${BUNDLE}" \
            -AppleLanguages "(en)" -AppleLocale en_US -homeResetDatabase -freezeSyncState "$@" >/dev/null 2>&1
    fi
    sleep 6
    if xcrun simctl io "${DEVICE}" screenshot "${path}" >/dev/null 2>&1; then
        CAPTURED+=("${name}")
        record_manifest "${name}"
        echo "  ok   ${path}"
    else
        echo "  FAIL ${path}" >&2
    fi
}

# alias_shot <captured-name> <second-name>...
# Two task ids can be the record of the SAME frame - the same appearance, the
# same launch arguments, one picture. Shooting it twice under two names does not
# double the coverage; it doubles the launches and creates a pair that DRIFTS,
# because in practice only one of the two ever gets re-shot. Every such pair in
# this file was last written by a different commit on a different date: on
# 2026-09-09 `P1.4-home` was current and `P1.1-shell-dark`, its identical twin,
# was six builds stale - a confident picture of the wrong code, which is the
# exact failure the SKIP_BUILD comment above warns about.
# So the frame is captured ONCE and copied to the other names. The names survive
# (briefs, docs/SITE.md and site/ reference them by filename), the record stays
# per-task, and the two files can no longer disagree.
# It copies only a frame THIS run produced: with FILTER set, a skipped canonical
# must not overwrite its alias with a stale file.
alias_shot() {
    local from="$1"; shift
    local name
    # `set -u` plus bash 3.2 (what macOS ships) treats "${empty[@]}" as unbound,
    # so an all-filtered run must bail before the expansion, not inside it.
    if [ "${#CAPTURED[@]}" -eq 0 ]; then
        echo "  skip ${from} was not captured this run; its aliases are unchanged"
        return 0
    fi
    for name in "${CAPTURED[@]}"; do
        if [ "${name}" = "${from}" ]; then
            for name in "$@"; do
                cp "${OUT}/${from}.png" "${OUT}/${name}.png"
                record_manifest "${name}"
                echo "  ok   ${OUT}/${name}.png (copy of ${from})"
            done
            return 0
        fi
    done
    echo "  skip ${from} was not captured this run; its aliases are unchanged"
}

# Each task's screen, in task order. Both languages except where a task's
# screenshot is deliberately single-language (the light-theme shell, and the
# rejected accent-tab-bar record kept from P1.1).
capture P1.2-add-vehicle           en -presentScreen addVehicle
capture P1.2-add-vehicle-ru        ru -presentScreen addVehicle
capture P1.3-confirm-manual        en -seedVehicleForUITests -presentScreen confirmManual
capture P1.3-confirm-manual-ru     ru -seedVehicleForUITests -presentScreen confirmManual
capture P1.4-home                  en -seedHomeFullHistory
capture P1.4-home-ru               ru -seedHomeFullHistory
capture P1.4-home-empty            en -seedHomeEmptyVehicle
capture P1.4-home-empty-ru         ru -seedHomeEmptyVehicle
# P1.1's dark shell IS the Home frame - the same seed, the same appearance. It
# is kept as a name because docs/SITE.md, site/hugo.toml and two briefs cite it,
# and because P1.1-shell-light is only legible next to a dark counterpart.
alias_shot P1.4-home P1.1-shell-dark
# P1.5's subject is the LOG STREAM, which lives below the fold: shot unscrolled
# it produced a second copy of P1.4-home and never showed a log row. RV.103's
# `-homeScrollLogReveal` parks Home at the reveal seam, and RV.103's own seed is
# the history long enough to have one.
capture P1.5-log-stream            en -seedHomeRV103Reveal -homeScrollLogReveal
capture P1.5-log-stream-ru         ru -seedHomeRV103Reveal -homeScrollLogReveal
capture P1.6-edit-entry            en -seedEditEntry -presentScreen editEntry
capture P1.6-edit-entry-ru         ru -seedEditEntry -presentScreen editEntry
# RV.188: the neighbourhood panel's both-`.none` case with a NEXT entry - three
# labelled chart points and one sentence per culprit. `-editEntryFlagged` opens
# the middle flagged fill (a non-newest entry no real tap can reach, because
# `-presentScreen editEntry` always opens the newest).
capture RV.188-neighbourhood       en -seedEditEntryConflictMiddle -editEntryFlagged -presentScreen editEntry -scrollToNeighbourhood
capture RV.188-neighbourhood-ru    ru -seedEditEntryConflictMiddle -editEntryFlagged -presentScreen editEntry -scrollToNeighbourhood
# PJ.2's subject - the receipt card a scanned save now persists - sits at the
# top of this very frame, so PJ.2's record is this picture under its own name.
alias_shot P1.6-edit-entry    PJ.2-edit-entry-receipt
alias_shot P1.6-edit-entry-ru PJ.2-edit-entry-receipt-ru
capture P1.7-recently-deleted      en -seedRecentlyDeleted -presentScreen recentlyDeleted
capture P1.7-recently-deleted-ru   ru -seedRecentlyDeleted -presentScreen recentlyDeleted
# PJ.7's deleted reminder is a row on this list - the same frame.
alias_shot P1.7-recently-deleted    PJ.7-deleted-reminder
alias_shot P1.7-recently-deleted-ru PJ.7-deleted-reminder-ru
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
# P5.5b's per-car export row is a row ON Vehicle detail - the same frame.
alias_shot P1.12-vehicle-detail    P5.5b-export
alias_shot P1.12-vehicle-detail-ru P5.5b-export-ru
# PJ.45: the editable pace limit sits below the fold, so the pose scrolls it to
# the top of the viewport (simctl cannot scroll).
capture PJ.45-pace-limit           en -seedHomeCarSwitcher -presentScreen vehicleDetail -scrollToPaceLimit
capture PJ.45-pace-limit-ru        ru -seedHomeCarSwitcher -presentScreen vehicleDetail -scrollToPaceLimit
capture P2.1-capture               en -presentScreen capture -cameraStatus authorized
capture P2.1-capture-ru            ru -presentScreen capture -cameraStatus authorized
# The four-chip worst case: only a plug-in hybrid is offered both Fill-up and
# Charge, and Russian is where four chips stop fitting. Committed so the mode
# row's degradation is on the record, not assumed.
capture P2.1-capture-phev-ru       ru -presentScreen capture -cameraStatus authorized -powertrain phev

# P6.10: the alpha-testing disclosure on the capture surface (docs/ERRORS.md ->
# Capture). A fresh database is the point: with zero captures the notice is
# active, sitting directly above the shutter. `-alphaNoticeReset` clears the
# dismissal state so the notice renders even after a prior test/run dismissed it
# (UserDefaults survive `-homeResetDatabase`). RU is where the multi-line notice
# wraps longest ("...продолжайте снимать и отнеситесь с пониманием к
# ошибкам."), and the XL shot is the overflow check at a Dynamic Type the
# footnote actually scales to - the disclosure must grow without pushing the
# shutter off-screen.
capture P6.10-capture              en -presentScreen capture -cameraStatus authorized -alphaNoticeReset
capture P6.10-capture-ru           ru -presentScreen capture -cameraStatus authorized -alphaNoticeReset
capture P6.10-capture-ru-xl        ru -presentScreen capture -cameraStatus authorized \
  -alphaNoticeReset -UIPreferredContentSizeCategoryName UICTContentSizeCategoryXL

# P2.3: the scanned path lands in the SAME ConfirmManual sheet. The main pair
# shows the partly-resolved reality (liters + price pre-filled and dimmed, the
# total deriving), and -empty-ru the hard-rule-15 state: an all-nil extraction
# renders as the ordinary empty form - the state whose Russian labels overflow
# worst ("Enter total and liters to save" -> "Введите сумму и литры, чтобы
# сохранить").
capture P2.3-confirm            en -seedVehicleForUITests -presentScreen confirmManual -seedConfirmPrefill
capture P2.3-confirm-ru         ru -seedVehicleForUITests -presentScreen confirmManual -seedConfirmPrefill
capture P2.3-confirm-empty-ru   ru -seedVehicleForUITests -presentScreen confirmManual -seedConfirmPrefillEmpty

# P2.4: the mixed-receipt "Also on this receipt" section - the fuel line stands
# as the fill-up, the car wash defaults to accepted, the coffee to skipped.
capture P2.4-confirm-mixed      en -seedVehicleForUITests -presentScreen confirmManual -seedConfirmPrefillMixedReceipt
capture P2.4-confirm-mixed-ru   ru -seedVehicleForUITests -presentScreen confirmManual -seedConfirmPrefillMixedReceipt

# P2.5: the foreign-currency conversion card (289.50 PLN -> 67.79 EUR at the
# seed pack's 4.2706), plus the rate-pending variant where the entry date is
# outside the seed pack (original amount exact, home amount absent).
capture P2.5-confirm-foreign        en -seedVehicleForUITests -presentScreen confirmManual -seedConfirmForeign
capture P2.5-confirm-foreign-ru     ru -seedVehicleForUITests -presentScreen confirmManual -seedConfirmForeign
capture P2.5-confirm-foreign-pending    en -seedVehicleForUITests -presentScreen confirmManual -seedConfirmForeignPending
capture P2.5-confirm-foreign-pending-ru ru -seedVehicleForUITests -presentScreen confirmManual -seedConfirmForeignPending
# P5.2b's next-step row is ON the rate-pending card this frame already shows.
alias_shot P2.5-confirm-foreign-pending    P5.2b-confirm-pending-next-step
alias_shot P2.5-confirm-foreign-pending-ru P5.2b-confirm-pending-next-step-ru

# P5.2b: the rate-pending card flipped to converted from a manual rate (source
# "Manual"), and the F9 "N entries pending rates" footnote on Trends and Home.
# Its missing-next-step shot is the P2.5 frame above, aliased there. RU is where "Изменить курс" and "N записей ждут курс" are
# tightest.
capture P5.2b-confirm-manual-rate           en -seedVehicleForUITests -presentScreen confirmManual -seedConfirmForeignPending -manualRate 4.2706
capture P5.2b-confirm-manual-rate-ru        ru -seedVehicleForUITests -presentScreen confirmManual -seedConfirmForeignPending -manualRate 4.2706
capture P5.2b-trends-pending-footnote       en -seedHomePendingRates -selectTrendsTab
capture P5.2b-trends-pending-footnote-ru    ru -seedHomePendingRates -selectTrendsTab
capture P5.2b-home-pending-footnote         en -seedHomePendingRates
capture P5.2b-home-pending-footnote-ru      ru -seedHomePendingRates

# RV.111: the F9 footnote's dead end. Old (2015) pending rows are outside the
# rolling pack window; `-runRateDemandDrain` fires one demand check a beat
# after launch and `-stubRatesEmpty` answers it empty (provider reached, no
# row for those dates), so the footnote flips from "Check for rates" to the
# manual-rate line. RU is where the count and the dead-end caption are tightest.
capture RV.111-home-rates    en -seedHomeRV111OldPending -stubRatesEmpty -runRateDemandDrain
capture RV.111-home-rates-ru ru -seedHomeRV111OldPending -stubRatesEmpty -runRateDemandDrain

# RV.29: the fix for a foreign price wearing the home symbol. A RUB-home car
# whose most recent fill was paid in EUR and carries its conversion snapshot -
# the price tile shows the CONVERTED home figure (`168.333 ₽`), never the raw
# `1.919` the old code stamped `₽` on. The RU shot is the same number (the
# decimal separator is pinned), so it is the tile label lengths that stay in
# frame, not the figure.
capture RV.29-home-vitals         en -seedHomeRV29Foreign
capture RV.29-home-vitals-ru      ru -seedHomeRV29Foreign

# P2.3c (correcting P2.3b): the Fuel row offers a LIKELY set, never a limit -
# petrol grades share a tank, so a car whose kinds include any petrol grade is
# offered ALL petrol grades plus its other kinds, and the "+" menu reaches every
# other kind. The multi shot is a real bi-fuel car (petrol + LPG) - the row
# shows 92/95/98/100 + LPG plus the "+"; the single shot is a single-kind diesel
# car, the one case that still renders a static value (it stays correctable,
# hard rule 13). RU is where the static value's labels ("Дизель") and the chip
# row overflow worst.
capture P2.3b-confirm-fuel-multi     en -seedVehicleForUITests -presentScreen confirmManual -seedVehiclePetrolLPG -screenshotPrefill
capture P2.3b-confirm-fuel-multi-ru  ru -seedVehicleForUITests -presentScreen confirmManual -seedVehiclePetrolLPG -screenshotPrefill
capture P2.3b-confirm-fuel-single    en -seedVehicleForUITests -presentScreen confirmManual -seedVehicleDieselOnly -screenshotPrefill
capture P2.3b-confirm-fuel-single-ru ru -seedVehicleForUITests -presentScreen confirmManual -seedVehicleDieselOnly -screenshotPrefill


# PJ.8: the same Home entry after the S8 backfill filled it - a rate that
# arrived later (the `-stubRates` pack, dates outside the bundled seed) converts
# the three pending PLN rows to EUR, silently (no toast, no footnote). The
# converted amounts sit at the top of the log stream (the PLN fills are the
# newest), so the subject is in frame without scrolling.

# P3.1a: the typed ServiceEntry screen - the artboard state (two line items),
# and the lump-sum variant (one uncategorized item carrying the whole total).
capture P3.1a-service-entry            en -seedServiceEntry -presentScreen serviceEntry
capture P3.1a-service-entry-ru         ru -seedServiceEntry -presentScreen serviceEntry
capture P3.1a-service-entry-lump-sum   en -seedServiceEntryLumpSum -presentScreen serviceEntry
capture P3.1a-service-entry-lump-sum-ru ru -seedServiceEntryLumpSum -presentScreen serviceEntry

# P3.1b: the scanned invoice path - the split invoice with its page strip, and
# the honest failed-split lump-sum outcome (a normal state, never an error).
capture P3.1b-service-scan            en -seedServiceEntryScan -presentScreen serviceEntry
capture P3.1b-service-scan-ru         ru -seedServiceEntryScan -presentScreen serviceEntry
capture P3.1b-service-scan-lump-sum   en -seedServiceEntryScanLumpSum -presentScreen serviceEntry
capture P3.1b-service-scan-lump-sum-ru ru -seedServiceEntryScanLumpSum -presentScreen serviceEntry

# P3.2: the parts shelf (its visible "on shelf" state) and the ServiceEntry Link
# row offering a matching shelf part.
capture P3.2-parts-shelf       en -seedPartsShelf -presentScreen partsShelf
capture P3.2-parts-shelf-ru    ru -seedPartsShelf -presentScreen partsShelf
capture P3.2-service-link      en -seedServiceEntryLink -presentScreen serviceEntry
capture P3.2-service-link-ru   ru -seedServiceEntryLink -presentScreen serviceEntry

# PJ.25: the shelf reached from the Garage as a PUSHED screen (the Vehicle
# detail row's door) - the `partsShelfPushed` pose, distinct from P3.2's nested
# sheet pose. The filled pair shows the seeded parts; the empty pair shows the
# shelf's own empty state for a car with nothing on it (hard rule 7). RU is
# where the nav title ("Полка запчастей") and the row subtitle run longest.
capture PJ.25-parts-shelf        en -seedPartsShelf -presentScreen partsShelfPushed
capture PJ.25-parts-shelf-ru     ru -seedPartsShelf -presentScreen partsShelfPushed
capture PJ.25-parts-shelf-empty    en -seedHomeCarSwitcher -presentScreen partsShelfPushed
capture PJ.25-parts-shelf-empty-ru ru -seedHomeCarSwitcher -presentScreen partsShelfPushed

# PJ.11: the F9a conflict on the service save - a service odometer below its
# date-neighbour (119 486 -> 11 948) shows the amber warning and Fix, and the
# save is never blocked (hard rule 13). The seed pairs the prior-fill vehicle
# with a conflicting odometer pre-fill.
capture PJ.11-service-flagged    en -seedVehicleForUITests -seedServiceEntryConflict -presentScreen serviceEntry
capture PJ.11-service-flagged-ru ru -seedVehicleForUITests -seedServiceEntryConflict -presentScreen serviceEntry

# PJ.34: the F9a ranked fixes on the Confirm sheet. The scanned prefill carries
# a printed date (17.08.2026), so the validator ranks "Fix odometer" first and
# preselects it; the second pair shows the override confirmation naming the
# receipt's date. `-screenshotOdometer 120000` puts the reading ABOVE the seeded
# prior fill - the scanned date is earlier, so only a higher reading breaks the
# order check and flags.
capture PJ.34-f9a-ranked-fixes       en -seedVehicleForUITests -seedConfirmPrefill -presentScreen confirmManual -screenshotOdometer 120000
capture PJ.34-f9a-ranked-fixes-ru    ru -seedVehicleForUITests -seedConfirmPrefill -presentScreen confirmManual -screenshotOdometer 120000
capture PJ.34-f9a-date-confirmation    en -seedVehicleForUITests -seedConfirmPrefill -presentScreen confirmManual -screenshotOdometer 120000 -screenshotDateConfirmation
capture PJ.34-f9a-date-confirmation-ru ru -seedVehicleForUITests -seedConfirmPrefill -presentScreen confirmManual -screenshotOdometer 120000 -screenshotDateConfirmation

# P3.4: the Reminders list (attention + scheduled groups), the empty state,
# and the reminder form. RU is where the trailing chip ("12 дней") and the
# section labels ("ТРЕБУЕТ ВНИМАНИЯ") are tightest.
capture P3.4-reminders            en -seedReminders -presentScreen reminders
capture P3.4-reminders-ru         ru -seedReminders -presentScreen reminders
# PJ.4's list shot is this same screen under the same seed.
alias_shot P3.4-reminders    PJ.4-reminders
alias_shot P3.4-reminders-ru PJ.4-reminders-ru
capture P3.4-reminders-empty      en -presentScreen reminders
capture P3.4-reminders-empty-ru   ru -presentScreen reminders
capture P3.4-reminder-form        en -seedReminders -seedReminderForm -presentScreen reminderForm
capture P3.4-reminder-form-ru     ru -seedReminders -seedReminderForm -presentScreen reminderForm

# P3.5: the completion sheet (recurring, so the next-cycle line shows) and the
# entry screen carrying the reminder pre-fill. `-presentReminderComplete`
# auto-opens the sheet over the seeded oil change - simctl cannot tap.
capture P3.5-reminder-complete           en -seedReminderComplete -presentScreen reminders -presentReminderComplete
capture P3.5-reminder-complete-ru        ru -seedReminderComplete -presentScreen reminders -presentReminderComplete
capture P3.5-reminder-complete-prefill    en -seedReminderCompletionPrefill -presentScreen serviceEntry
capture P3.5-reminder-complete-prefill-ru ru -seedReminderCompletionPrefill -presentScreen serviceEntry

# P3.6: the one-time notification-permission card (denied) in place on the
# Reminders list, EN and RU. `-notificationStatus denied` forces the
# authorization state so the card renders without a real permission dialog.
capture P3.6-notifications-denied    en -seedReminders -notificationStatus denied -presentScreen reminders
capture P3.6-notifications-denied-ru ru -seedReminders -notificationStatus denied -presentScreen reminders

# P3.3: the tire-set list (one set with derived mileage, one with "–") and the
# ServiceEntry Tires mode mounting a set (odometer required, pre-filled).
capture P3.3-tire-sets            en -seedTireSets -presentScreen tireSets
capture P3.3-tire-sets-ru         ru -seedTireSets -presentScreen tireSets
capture P3.3-tire-mount           en -seedTireSets -presentScreen serviceEntry -seedServiceEntryTires
capture P3.3-tire-mount-ru        ru -seedTireSets -presentScreen serviceEntry -seedServiceEntryTires

# PJ.26: the `.parts` expense's "Make this a tire set" door on the Edit entry
# screen. RU is where the label runs longest against the dashed card.
capture PJ.26-tire-set-door       en -seedEditEntryScannedExpense -presentScreen editEntry
capture PJ.26-tire-set-door-ru    ru -seedEditEntryScannedExpense -presentScreen editEntry

# PJ.27: the seasonal swap offer a tire mount proposes, over the seeded mount.
# It is the same offer sheet as RV.77, with the six-month cadence and the set's
# own name; the RU shot is where the title and the interval caption run longest.
capture PJ.27-swap-reminder       en -seedSwapReminderOffer -presentServiceReminderOffer
capture PJ.27-swap-reminder-ru    ru -seedSwapReminderOffer -presentServiceReminderOffer

# PJ.22: the line item's km / months lifetime editor on the Edit-entry service
# screen, and the offer the lifetime it states raises (brakes, a category with no
# curated interval). RU is where "15 000 км или 12 мес" on one row runs longest.
capture PJ.22-service-lifetime       en -seedEditEntryService -presentScreen editEntry
capture PJ.22-service-lifetime-ru    ru -seedEditEntryService -presentScreen editEntry
capture PJ.22-service-lifetime-offer    en -seedServiceLifetimeOffer -presentServiceReminderOffer
capture PJ.22-service-lifetime-offer-ru ru -seedServiceLifetimeOffer -presentServiceReminderOffer

# P4.4: the Sign in sheet (with the warn-amber "pick one and keep it" notice at
# the decision moment) and the J11a wrong-provider question (empty account +
# "Already use Tankbook?"). RU is where the amber notice - a paragraph - is the
# shape that overflows. The wrong-provider shot is the REAL path since PJ.3: the
# Welcome root's third path carries the restore intent, `-signInStubAuth` runs a
# real sign-in through the stubs, and `-signInAutoStart` drives the tap `simctl`
# cannot make.
capture P4.4-sign-in              en -presentScreen signIn
capture P4.4-sign-in-ru           ru -presentScreen signIn
capture P4.4-wrong-provider       en -presentWelcome -presentScreen signIn -signInStubAuth -signInAutoStart
capture P4.4-wrong-provider-ru    ru -presentWelcome -presentScreen signIn -signInStubAuth -signInAutoStart

# P4.7: restore end-to-end - the Restoring screen (verification stats before
# finishing), the empty-restore recovery entry point (F7's merge-conflict
# prevention), and the backend-down state (the honest F7 copy with its next
# step, never a generic error).
capture P4.7-restoring            en -presentScreen signIn -signInRestore
capture P4.7-restoring-ru         ru -presentScreen signIn -signInRestore
capture P4.7-restore-empty        en -presentScreen signIn -signInRestoreEmpty
capture P4.7-restore-empty-ru     ru -presentScreen signIn -signInRestoreEmpty
capture P4.7-restore-unreachable  en -presentScreen signIn -signInRestoreUnreachable
capture P4.7-restore-unreachable-ru ru -presentScreen signIn -signInRestoreUnreachable

# P4.9b: the Settings sync surface, six states (guest, synced, pending, flagged,
# revoked, quota). The status row is reassurance and never turns amber with age;
# the flagged row is a derived count and a link only (hard rule 8). RU is where
# "Waiting to sync · 5 changes" and "2 entries need a look" overflow worst - RU
# runs 20-30% longer and short strings expand.
capture P4.9b-settings-guest      en -presentScreen settings -seedSettingsGuest
capture P4.9b-settings-guest-ru   ru -presentScreen settings -seedSettingsGuest
capture P4.9b-settings-synced     en -presentScreen settings -seedSettingsSynced
capture P4.9b-settings-synced-ru  ru -presentScreen settings -seedSettingsSynced
capture P4.9b-settings-pending    en -presentScreen settings -seedSettingsPending
capture P4.9b-settings-pending-ru ru -presentScreen settings -seedSettingsPending
capture P4.9b-settings-flagged    en -presentScreen settings -seedSettingsFlagged
capture P4.9b-settings-flagged-ru ru -presentScreen settings -seedSettingsFlagged
capture P4.9b-settings-revoked    en -presentScreen settings -seedSettingsRevoked
capture P4.9b-settings-revoked-ru ru -presentScreen settings -seedSettingsRevoked
capture P4.9b-settings-quota      en -presentScreen settings -seedSettingsQuota
capture P4.9b-settings-quota-ru   ru -presentScreen settings -seedSettingsQuota

# PJ.13: the J11a just-signed-in card - "Synced just now · 1 device" and the
# "Your garage now follows your account" confirmation (docs/JOURNEYS.md J11a ->
# First push / Confirm). The seed renders the post-first-push state under a
# frozen sync; RU is where the confirmation and the device-count line are the
# overflow check.
capture PJ.13-settings-signed-in      en -presentScreen settings -seedSettingsSignedIn
capture PJ.13-settings-signed-in-ru   ru -presentScreen settings -seedSettingsSignedIn

# P6.11: a server ahead of the app surfaces on the Settings account card -
# version-first copy (update, never an upsell). The upgrade shot is the amber
# attention notice; the rate-limited shot is the reassurance wait.
capture P6.11b-settings-upgrade        en -presentScreen settings -seedSettingsUpgradeRequired
capture P6.11b-settings-upgrade-ru     ru -presentScreen settings -seedSettingsUpgradeRequired
capture P6.11b-settings-ratelimited    en -presentScreen settings -seedSettingsRateLimited
capture P6.11b-settings-ratelimited-ru ru -presentScreen settings -seedSettingsRateLimited

# P6.1b: the J9 anomaly insight card in the Log (docs/JOURNEYS.md J9). The
# collapsed card states the drift and the compared window; `-presentAnomalyEvidence`
# expands it (the chart + causes + the two actions); `-presentAnomalyDismissal`
# puts the dismiss-reason sheet on top - simctl cannot tap, so the hooks drive
# the state a screenshot needs. RU is where the composed phrases run longest
# ("Расход вырос на 21% по сравнению с прошлым годом" and the two-value caption).
capture P6.1b-insight-card              en -seedHomeAnomaly
capture P6.1b-insight-card-ru           ru -seedHomeAnomaly
capture P6.1b-insight-evidence          en -seedHomeAnomaly -presentAnomalyEvidence
capture P6.1b-insight-evidence-ru       ru -seedHomeAnomaly -presentAnomalyEvidence
capture P6.1b-insight-dismiss           en -seedHomeAnomaly -presentAnomalyDismissal
capture P6.1b-insight-dismiss-ru        ru -seedHomeAnomaly -presentAnomalyDismissal

# P6.3: the gateway on the Confirm sheet (docs/API.md -> "The device's side of
# /extract"). The timeout shot is the 3 s budget-expired state - the message
# names the next step (carry on with what was read locally) and carries no
# upsell (hard rule 7). `-seedGatewayDelay 30` keeps the request in flight past
# the 6 s capture window so the banner is the stable state. The late-answer shot
# shows the gateway's fields landed as SUGGESTIONS: the sparse prefill resolved
# liters on-device, the cloud reading fills the blank total and price (the
# `-seedGatewayConsistent` triple locks cleanly). The filled fields render
# BRIGHT here, not dimmed: they land dimmed like any extraction suggestion, and
# `ConfirmConfidenceGate` un-dims them the moment the cross-check locks (P2.3).
# The timeout shot above is where the dim is visible, on the one sparse value.
# Editable throughout either way, which is what hard rule 13 actually requires.
capture P6.3-gateway-timeout          en -seedVehicleForUITests -presentScreen confirmManual -seedConfirmPrefillSparse -seedGateway -seedGatewayDelay 30
capture P6.3-gateway-timeout-ru       ru -seedVehicleForUITests -presentScreen confirmManual -seedConfirmPrefillSparse -seedGateway -seedGatewayDelay 30
capture P6.3-gateway-late-answer      en -seedVehicleForUITests -presentScreen confirmManual -seedConfirmPrefillSparse -seedGateway -seedGatewayConsistent -seedGatewayDelay 4
capture P6.3-gateway-late-answer-ru   ru -seedVehicleForUITests -presentScreen confirmManual -seedConfirmPrefillSparse -seedGateway -seedGatewayConsistent -seedGatewayDelay 4

# P4.6: the "photo syncing" shimmer - an entry whose inline thumbnail has
# arrived (in the payload) but whose full rendition blob is still pending. The
# chip shimmers and the entry is openable and editable throughout.
capture P4.6-photo-syncing        en -seedPhotoSyncing -presentScreen editEntry
capture P4.6-photo-syncing-ru     ru -seedPhotoSyncing -presentScreen editEntry

# PJ.28: a saved SCANNED EXPENSE showing its attached receipt - the row's whole
# point (a scan's photograph used to be thrown away). `-seedEditEntryScannedExpense`
# persists exactly what the real scanned save writes (ExpenseReceiptWrite over a
# synthetic frame), so the receipt strip and its "Scanned" line are the shipped
# shape, not a painted state. RU is where "Receipt photo"/"Добавить"/"Scanned"
# copy and the expense fields are the overflow check.
capture PJ.28-expense    en -seedEditEntryScannedExpense -presentScreen editEntry
capture PJ.28-expense-ru ru -seedEditEntryScannedExpense -presentScreen editEntry

# PJ.23: a SERVICE opened in Edit entry showing its editable line items - the
# work, its category and its cost, which the screen used to hide entirely
# (only a Vendor field rendered) while RV.187 titled the Log row from the first
# named item. The seed's second item carries a custom `.other(...)` category so
# the frame shows both the chooser and the free-text field; the first carries a
# partNumber/lifetime the screen does not edit but must not drop. RU is where a
# category label beside a cost on one row is the overflow check.
#
# RV.198 (2026-09-10): the same pose now carries the **Add line item** button
# under the items and a trash affordance on each row, so the frame is captured
# once and aliased - the two names are one picture, and shooting it twice would
# let them drift. RU is where a delete affordance plus a cost on one row bites.
#
# RV.202 (2026-09-11): the same service arrives with NO attachment, so the frame
# now also shows the "Add receipt" affordance on the receipt strip - the
# non-fill form used to render no card at all for such an entry. Aliased to the
# same picture rather than shot twice: the seed and the appearance are identical.
capture PJ.23-service-items    en -seedEditEntryService -presentScreen editEntry
capture PJ.23-service-items-ru ru -seedEditEntryService -presentScreen editEntry
alias_shot PJ.23-service-items    RV.198-service-items RV.202-service-receipt
alias_shot PJ.23-service-items-ru RV.198-service-items-ru RV.202-service-receipt-ru

# RV.199 (2026-09-11): a service's line sum stated beside its independently
# editable Amount, with the disagreement marked as ATTENTION - never a gate and
# never a rewrite of the user's total (hard rule 13). The first pose's stored
# Amount (160.00) differs from its lines (89.00 + 59.00 = 148.00), the honest
# invoice shape (tax, a discount, an un-itemised line). The second pose's items
# span currencies (89.00 EUR + 59.00 USD), so the card states the per-currency
# breakdown and NEVER a summed cross-currency total (hard rule 3, RV.145). RU is
# where "Позиции" plus a mismatch sentence on one card is the overflow check.
capture RV.199-service-sum      en -seedEditEntryServiceMismatch -presentScreen editEntry
capture RV.199-service-sum-ru   ru -seedEditEntryServiceMismatch -presentScreen editEntry
capture RV.199-service-mixed      en -seedEditEntryServiceMixedCurrency -presentScreen editEntry
capture RV.199-service-mixed-ru   ru -seedEditEntryServiceMixedCurrency -presentScreen editEntry

# RV.149: the shared "receipt photo could not be kept" toast (docs/ERRORS.md ->
# Confirm, RV.149) - the message a fill-up save shows after its photo write
# fails, rendered by the real toast host over Home. A pose: the exact line the
# save runs, held on screen by `-freezeToasts` (the real toast auto-dismisses in
# 4 s, which no `sleep 6` capture could catch). RU is where the sentence runs
# longest and must not truncate its next step (hard rule 7).
# The seed is `-seedHomeFullHistory`, NOT the bare Confirm vehicle: with the
# latter Home renders its empty "Add your first car" state, so the frame showed
# a correct toast in a state no user can reach - you cannot save a fill-up with
# no car. A toast over an impossible screen is the "wrong seed looks like a
# successful capture" failure this file warns about at the end.
capture RV.149-receipt-not-saved    en -seedHomeFullHistory -screenshotReceiptNotSavedToast -freezeToasts
capture RV.149-receipt-not-saved-ru ru -seedHomeFullHistory -screenshotReceiptNotSavedToast -freezeToasts

# RV.10: the date row's picker OPEN on the Edit-entry screen - the flipped
# (up) chevron and the whole-row collapse affordance above the calendar, the
# two cues that make the no-change exit discoverable. `-openDatePicker` drives
# the state simctl cannot tap. The typed history's newest fill has no receipt
# card, so the date row is the top card and fills the frame. RU is where the
# picker's month/controls copy runs longest.
capture RV.10-date-picker-open    en -seedHomeEditHistory -presentScreen editEntry -openDatePicker
capture RV.10-date-picker-open-ru ru -seedHomeEditHistory -presentScreen editEntry -openDatePicker

# PJ.48: the "Add receipt" affordance on a TYPED entry's empty receipt card, and
# the post-attach state - the receipt linked and the OCR's unitPrice suggestion
# sitting on the blank price field, dimmed until confirmed (hard rule 13). RU is
# where "Add receipt" ("Добавить чек") runs longest; the dimmed suggestion must
# stay visibly dimmer than the typed total and liters beside it.
capture PJ.48-edit-add-receipt    en -seedEditEntryTyped -presentScreen editEntry
capture PJ.48-edit-add-receipt-ru ru -seedEditEntryTyped -presentScreen editEntry
capture PJ.48-edit-suggestion     en -seedEditEntryTypedAttached -presentScreen editEntry -seedAttachSuggestion
capture PJ.48-edit-suggestion-ru  ru -seedEditEntryTypedAttached -presentScreen editEntry -seedAttachSuggestion

# P5.5b: the import wizard's three screens (source picker, preview gate, review
# list) plus the per-car export row on Vehicle detail. The picker renders the
# stub transport's list; the preview/review install a stub parse (no file
# picker, no server). RU is where the longest copy overflows - the review intro
# is a two-count sentence and the duplicate warning is a paragraph.
# `shipped` is the stub that mirrors what `ImportFormats.cs` actually registers
# (RV.190). The canonical source shot used `one`, a single-format fixture from
# before the Drivvo parser landed, so the visual record showed a picker offering
# one importer AND a "Not yet" chip for Drivvo - a state the product has not been
# in since that parser shipped. A screenshot of a fixture nobody ships is not a
# record of the app.
capture P5.5b-import-source     en -presentScreen importWizard -importStubFormats shipped
capture P5.5b-import-source-ru  ru -presentScreen importWizard -importStubFormats shipped
# PJ.33's "How to export" link rides the format row on this same screen.
alias_shot P5.5b-import-source    PJ.33-import-guide
alias_shot P5.5b-import-source-ru PJ.33-import-guide-ru
capture P5.5b-import-preview    en -presentScreen importWizard -importStubParse mfm -seedImportPreview
capture P5.5b-import-preview-ru ru -presentScreen importWizard -importStubParse mfm -seedImportPreview
# PJ.10's once-per-file date question is the gate ON this preview - same frame.
alias_shot P5.5b-import-preview    PJ.10-import-date-question
alias_shot P5.5b-import-preview-ru PJ.10-import-date-question-ru
capture P5.5b-import-review     en -presentScreen importWizard -importStubParse review -seedImportReview
capture P5.5b-import-review-ru  ru -presentScreen importWizard -importStubParse review -seedImportReview

# RV.185: the import lets the user name a car it creates, pre-filled with the
# derived suggestion (hard rule 13). **Both poses exist to put the FIELD in
# frame**, which the obvious ones do not: on the single-car preview the
# "Imports into" card sits below the figures table, so `-importScrollToTargetCar`
# parks the scroll on it; on the multi-car gate a lane's field lives inside that
# lane's own card, so `-seedImportCarsNewCar` makes the FIRST lane the new one
# (`-seedImportCarsDecided` makes the second, whose card starts at the fold).
capture RV.185-import-new-car-name    en -presentScreen importWizard -importStubFormats one -seedImportNewCar -importScrollToTargetCar
capture RV.185-import-new-car-name-ru ru -presentScreen importWizard -importStubFormats one -seedImportNewCar -importScrollToTargetCar
capture RV.185-import-cars-name       en -presentScreen importWizard -importStubFormats one -seedImportCarsNewCar
capture RV.185-import-cars-name-ru    ru -presentScreen importWizard -importStubFormats one -seedImportCarsNewCar

# PJ.36/PJ.38: the export lanes. `-presentExportShare` / `-presentCarExportShare`
# are DEBUG hooks that drive the SAME build the row's tap runs, because simctl
# cannot tap the share sheet open. The PJ.36 shot is Settings with the
# whole-account share sheet up; the PJ.38 shot is the car's CSV share sheet over
# Vehicle detail (RU is where "Export everything · always free" and the row's
# caption run longest).
capture PJ.36-export-share       en -presentScreen settings -seedSettingsPending -presentExportShare
capture PJ.36-export-share-ru    ru -presentScreen settings -seedSettingsPending -presentExportShare
capture PJ.38-car-export         en -seedHomeCarSwitcher -presentScreen vehicleDetail -presentCarExportShare
capture PJ.38-car-export-ru      ru -seedHomeCarSwitcher -presentScreen vehicleDetail -presentCarExportShare

# PJ.9: the review list's non-fuel row with its "Import as service" action. The
# service seed's review screen holds exactly one service row, so the action is
# in frame without scrolling. (PJ.10's date-format question - confirm stays
# disabled until answered - is the P5.5b preview frame above, aliased there.)
capture PJ.9-import-nonfuel-row        en -presentScreen importWizard -importStubFormats one -seedImportService
capture PJ.9-import-nonfuel-row-ru     ru -presentScreen importWizard -importStubFormats one -seedImportService

# PJ.11: the import review list showing a flagged-order row - the real MFM-style
# `9` odometer badged "Breaks the timeline" with its Fix and "Import as-is",
# before anything is written (F6a).
capture PJ.11-import-flagged-row    en -presentScreen importWizard -seedImportTimeline
capture PJ.11-import-flagged-row-ru ru -presentScreen importWizard -seedImportTimeline

# PR.6: the transport-timeout cancels (docs/PRACTICES.md U6). The import parse's
# Cancel - the source screen mid-upload, driven by the slow stub so `isParsing`
# is still true at the 6 s capture - and the restore progress's Cancel - the
# Restoring screen's photo download under `-seedRestoreProgress`. RU is the
# overflow check on both affordances.
capture PR.6-restore-cancel    en -presentScreen signIn -signInRestore -seedRestoreProgress
capture PR.6-restore-cancel-ru ru -presentScreen signIn -signInRestore -seedRestoreProgress

# PR.6b: the import parse Cancel made VISIBLE (not merely present) and the bar
# naming the reading state while parsing. The Cancel must render above the owned
# tab bar - the row exists because the PR.6 captures showed the affordance under
# it, present for the test and not for the user.
capture PR.6b-import-cancel    en -presentScreen importWizard -importStubFormats one -importStubParseSlow -seedImportParsing
capture PR.6b-import-cancel-ru ru -presentScreen importWizard -importStubFormats one -importStubParseSlow -seedImportParsing

# RV.68: the source screen's offline card is reserved for a GENUINE
# connectivity failure, and each non-offline load failure gets its own honest
# card - never the "Importing needs a connection" lie on an online device. The
# offline pair is the legitimate case (kept); the server and contract pairs are
# the new cards whose Russian copy runs longest ("Приложение и сервер не
# совпадают – повторите попытку и обновите Tankbook, если это не поможет.").
capture RV.68-import-offline      en -presentScreen importWizard -importTransportOffline
capture RV.68-import-offline-ru   ru -presentScreen importWizard -importTransportOffline
capture RV.68-import-servererror  en -presentScreen importWizard -importTransportScenario server
capture RV.68-import-servererror-ru ru -presentScreen importWizard -importTransportScenario server
capture RV.68-import-contract     en -presentScreen importWizard -importTransportScenario contract
capture RV.68-import-contract-ru  ru -presentScreen importWizard -importTransportScenario contract

# PJ.3b: the Welcome root (design/screens/Welcome.dc.html) - the fresh-install
# screen a reinstall or an Android migrant meets, with its three equal paths.
# `-presentWelcome` runs the REAL onboarding decision under the seed harness's
# reset. The light pair uses the light artboard (LightWelcome.dc.html) - this
# row has a light artboard, so light is not optional here. RU is where the
# feature lines and the third path's sentence run longest. PJ.3b replaced the
# "Point. Scan. Done." promise with the honest "A head start, not an answer"
# (hard rule 15) - the tagline is the subject of these frames, so it must be
# legible in every capture, EN and RU, dark and light.
capture PJ.3b-welcome         en -presentWelcome
capture PJ.3b-welcome-ru      ru -presentWelcome
# RV.23 re-argued this same dark frame: the third promise is two-sided instead
# of "No account needed", sign-in is a peer button naming what an account buys,
# and the returning user's line is one whole localised phrase (it used to be
# concatenated, which rendered the noun "Вход" where a verb belongs). RU is the
# frame that proves it - the door's benefit line is where the 20-30% expansion
# lands, and the restore line is where the old defect was visible. Same seed,
# same appearance, one picture; the light pair below is a different frame.
alias_shot PJ.3b-welcome    RV.23-welcome
alias_shot PJ.3b-welcome-ru RV.23-welcome-ru
xcrun simctl ui "${DEVICE}" appearance light >/dev/null 2>&1
capture PJ.3b-welcome-light      en -presentWelcome
capture PJ.3b-welcome-light-ru   ru -presentWelcome
xcrun simctl ui "${DEVICE}" appearance dark >/dev/null 2>&1

# PJ.4: the reminder banner is REAL data now (docs/ERRORS.md -> Home, row
# "Reminder due") - a seeded due reminder renders it with the reminder's own
# title and the actual count, never the old "Insurance renews in 12 days"
# fixture sentence. `-seedSettingsSignedIn` puts the launch on the signed-in
# layout (the banner renders there; a no-session launch is the guest chrome).
# The list shot is the screen the banner's View reaches, carrying the same
# attention row. RU is where the banner's count phrase ("Страховка через 12
# дней") and the list's chip run longest.
capture PJ.4-home-reminder    en -seedSettingsSignedIn -seedHomeReminderDue
capture PJ.4-home-reminder-ru ru -seedSettingsSignedIn -seedHomeReminderDue

# PJ.5: the notification deep link - a tapped reminder opens Reminders with
# the completion sheet for the REMINDER the identifier named (the fixed
# ReminderTestSeed.deepLinkReminderID "Insurance renewal"); a tapped monthly
# summary opens the Trends tab. `-replayNotificationResponse <identifier>`
# replays the tap without a real notification (the DEBUG hook). RU is where the
# sheet's phrases ("Страховка – выполнено") and the list's chip run longest.
capture PJ.5-reminder-tap    en -seedReminders -replayNotificationResponse reminder.0D4B0F2A-3E1C-4B6A-9C5D-8E7F1A2B3C4D.date
capture PJ.5-reminder-tap-ru ru -seedReminders -replayNotificationResponse reminder.0D4B0F2A-3E1C-4B6A-9C5D-8E7F1A2B3C4D.date
capture PJ.5-summary-tap     en -seedHomeFullHistory -replayNotificationResponse monthly-summary.3F2504E0-4F89-41D3-9A0C-0305E82C3301.2026-08
capture PJ.5-summary-tap-ru  ru -seedHomeFullHistory -replayNotificationResponse monthly-summary.3F2504E0-4F89-41D3-9A0C-0305E82C3301.2026-08

# PJ.7: a deleted reminder is a tombstone like any entry (hard rule 8) - it
# appears on Recently deleted with its countdown and a Restore (that list is the
# P1.7 frame above, aliased there), and deleting a reminder is reversible for 30
# days. The alert shot shows the CORRECTED delete confirmation - the 30-day
# truth, never "this can't be undone" (`-presentReminderDeleteAlert`, since
# simctl cannot tap the row menu). RU is where the alert sentence runs longest.
capture PJ.7-delete-alert         en -seedReminders -presentScreen reminders -presentReminderDeleteAlert
capture PJ.7-delete-alert-ru      ru -seedReminders -presentScreen reminders -presentReminderDeleteAlert

# PJ.6: "Type it" opens the form for the mode you are in (hard rule 15) - the
# capture surface in Service mode with the Service form open over it, driven by
# `-captureMode service` (the mode row shows Service selected beneath the sheet)
# and `-captureAutoTypeIt` (`simctl` cannot tap). The form in frame is the
# SERVICE form, not the fill-up one - that is the whole bug this row fixes. RU
# is where the sheet's labels run longest.
capture PJ.6-typeit-service    en -seedVehicleForUITests -presentScreen capture -cameraStatus authorized -captureMode service -captureAutoTypeIt
capture PJ.6-typeit-service-ru ru -seedVehicleForUITests -presentScreen capture -cameraStatus authorized -captureMode service -captureAutoTypeIt

# PJ.12: the EV capture surface with the dead Charge chip gone - the mode row
# holds exactly Service (selected - the EV now opens on a mode that works) and
# Expense, with no Charge chip in frame. RU is where the row's labels expand
# ("Обслуживание", "Расходы") and Service's default selection must survive it.
capture PJ.12-capture-ev    en -presentScreen capture -cameraStatus authorized -powertrain ev
capture PJ.12-capture-ev-ru ru -presentScreen capture -cameraStatus authorized -powertrain ev

# PJ.14: the live "+N km since last" odometer caption (docs/DESIGN.md -> the
# Pump Card) - the positive-delta state (120 000 vs the seeded 119 486 = +514)
# and the amber pace warn (130 000 over 6 days = 1 752/day > the seeded 1 500).
# `-screenshotOdometer` lands the value without typing; RU is where the caption
# runs longest ("+514 километров с прошлой заправки").
capture PJ.14-odometer-delta    en -seedVehicleForUITests -presentScreen confirmManual -screenshotOdometer 120000
capture PJ.14-odometer-delta-ru ru -seedVehicleForUITests -presentScreen confirmManual -screenshotOdometer 120000
capture PJ.14-odometer-warn     en -seedVehicleForUITests -presentScreen confirmManual -screenshotOdometer 130000
capture PJ.14-odometer-warn-ru  ru -seedVehicleForUITests -presentScreen confirmManual -screenshotOdometer 130000

# PJ.17: the empty-but-alive Confirm (docs/JOURNEYS.md F1) - a scan that
# resolved NOTHING but kept its photo. The quiet inkSoft caption is visible,
# Total is focused (keyboard up), and nothing is amber. The caption sits at the
# TOP of the sheet, above Date/Odometer/Fuel - Total's focus keeps the numbers
# card in view and must NOT scroll the caption out of frame; RU is where the
# caption ("Не удалось распознать – введите вручную, фото останется
# прикреплённым.") runs longest.

# PJ.20: About & feedback - the "Tell us" composer with the consent toggle (the
# load-bearing default-off opt-in) and the send row. RU is where the consent's
# explanation and the composed consent-required phrase run longest.
# PJ.20: the import "send us the file" consent step - the explicit consent line
# and the actual file name, before the share sheet. `-seedSendFile` drives the
# sheet with a seeded file (the system file picker cannot be tapped by simctl).
capture PJ.20-import-sendfile     en -presentScreen importWizard -importStubFormats one -seedSendFile
capture PJ.20-import-sendfile-ru  ru -presentScreen importWizard -importStubFormats one -seedSendFile

# RV.5: the capture review step - the shot, "Use this", "Re-take" and "Type it".
# `-captureAutoReview` presents it a beat after the surface appears, because
# `simctl` cannot tap a shutter; the image is a real corpus receipt read from
# the host path, so the screenshot shows what a user actually sees. RU is where
# the two peers are tightest: "Переснять" beside "Ввести вручную" on one row.
RV5_FIXTURE="$PWD/Spike/ReceiptSpike/fixtures/receipts/receipt-011-samara-diesel-ru.png"
capture RV.5-capture-review    en -seedVehicleForUITests -presentScreen capture -cameraStatus authorized \
  -captureFixtureImage "${RV5_FIXTURE}" -captureAutoReview
capture RV.5-capture-review-ru ru -seedVehicleForUITests -presentScreen capture -cameraStatus authorized \
  -captureFixtureImage "${RV5_FIXTURE}" -captureAutoReview

# RV.24: the Settings language picker (Option B, docs/TASKS.md RV.24) - the row's
# destination. The picker lists the app's real localizations plus "System
# default" (the way back to following the system); choosing one shows the restart
# prompt below, which names its next step (open the app again, never a
# programmatic exit - hard rule 7). `-presentLanguagePicker` opens the sheet
# (simctl cannot tap); `-languagePickerShowPrompt` preselects a language so the
# prompt renders. RU is where the prompt copy overflows ("Язык изменится при
# следующем открытии Tankbook").
capture RV.24-language            en -presentScreen settings -seedSettingsGuest -languageReset -presentLanguagePicker
capture RV.24-language-ru         ru -presentScreen settings -seedSettingsGuest -languageReset -presentLanguagePicker
capture RV.24-language-prompt     en -presentScreen settings -seedSettingsGuest -languageReset -presentLanguagePicker -languagePickerShowPrompt
capture RV.24-language-prompt-ru  ru -presentScreen settings -seedSettingsGuest -languageReset -presentLanguagePicker -languagePickerShowPrompt

# RV.22: the sync state chip beside the Settings gear - one shot per state, EN
# and RU, so each state actually renders (a shot of "Synced" five times proves
# nothing). The chip state is forced at launch (`-seedSyncChip*`) because it
# lives on the tab roots, before Settings' own seed runs. RU is the real test:
# "Ожидают отправки"/"Устройство отключено"/"Синхронизация…" are far longer
# than their English counterparts and a chip label is exactly where that
# overflows. The flagged shot is the warn dot riding the corner over "Synced".
capture RV.22-chip-signedout    en -seedHomeFullHistory -clearSessionAtLaunch -seedSyncChipSignedOut
capture RV.22-chip-signedout-ru ru -seedHomeFullHistory -clearSessionAtLaunch -seedSyncChipSignedOut
capture RV.22-chip-revoked      en -seedSettingsSignedIn -seedHomeFullHistory -seedSyncChipRevoked
capture RV.22-chip-revoked-ru   ru -seedSettingsSignedIn -seedHomeFullHistory -seedSyncChipRevoked
capture RV.22-chip-authexpired  en -seedSettingsSignedIn -seedHomeFullHistory -seedSyncChipAuthExpired
capture RV.22-chip-authexpired-ru ru -seedSettingsSignedIn -seedHomeFullHistory -seedSyncChipAuthExpired
capture RV.22-chip-quota        en -seedSettingsSignedIn -seedHomeFullHistory -seedSyncChipQuota
capture RV.22-chip-quota-ru     ru -seedSettingsSignedIn -seedHomeFullHistory -seedSyncChipQuota
capture RV.22-chip-syncing      en -seedSettingsSignedIn -seedHomeFullHistory -seedSyncChipSyncing
capture RV.22-chip-syncing-ru   ru -seedSettingsSignedIn -seedHomeFullHistory -seedSyncChipSyncing
capture RV.22-chip-waiting      en -seedSettingsSignedIn -seedHomeFullHistory -seedSyncChipWaiting
capture RV.22-chip-waiting-ru   ru -seedSettingsSignedIn -seedHomeFullHistory -seedSyncChipWaiting
capture RV.22-chip-synced       en -seedSettingsSignedIn -seedHomeFullHistory -seedSyncChipSynced
capture RV.22-chip-synced-ru    ru -seedSettingsSignedIn -seedHomeFullHistory -seedSyncChipSynced
capture RV.22-chip-flagged      en -seedSettingsSignedIn -seedHomeFullHistory -seedSyncChipSynced -seedSyncChipFlagged
capture RV.22-chip-flagged-ru   ru -seedSettingsSignedIn -seedHomeFullHistory -seedSyncChipSynced -seedSyncChipFlagged

# RV.38: the inbox bell and its item. The bell shot shows the count riding the
# header beside the chip and gear (the three-control placement this task had to
# justify with a measurement); the item shot shows the item's three actions.
# RU is the real test - "Обновить по чеку" / "Оставить как есть" / "Заменить
# чек" are where the 20-30% expansion lands in a crowded corner.
capture RV.38-bell           en -seedSettingsSignedIn -seedInboxItem -inboxReset
capture RV.38-bell-ru        ru -seedSettingsSignedIn -seedInboxItem -inboxReset
capture RV.38-inbox-item     en -seedSettingsSignedIn -seedInboxItem -inboxReset -presentScreen inbox
capture RV.38-inbox-item-ru  ru -seedSettingsSignedIn -seedInboxItem -inboxReset -presentScreen inbox

# RV.45: the per-field comparison card. The comparison seed is the "interesting
# case" - exactly one differing field (volume 40.00 vs 30.00) and one blank
# field (price), everything else agreeing, so the card shows the yours-vs-
# receipt table with two tickable rows and the distinct fill/replace verbs. RU
# is the real test: a two-column comparison with Russian field labels ("Литры",
# "Цена/л", "Итого", "Валюта") and the verbs ("Заменит введённое" / "Заполнит
# пустое поле") are exactly where a table overflows.
capture RV.45-comparison        en -seedSettingsSignedIn -seedInboxComparison -inboxReset -presentScreen inbox
capture RV.45-comparison-ru     ru -seedSettingsSignedIn -seedInboxComparison -inboxReset -presentScreen inbox
# RV.45: the nothing-to-change card - an item whose reading agrees with the
# saved entry must say so and offer no update action (honesty rule 2).
capture RV.45-nothing-to-change    en -seedSettingsSignedIn -seedInboxNothingToChange -inboxReset -presentScreen inbox
capture RV.45-nothing-to-change-ru ru -seedSettingsSignedIn -seedInboxNothingToChange -inboxReset -presentScreen inbox

# RV.201: the same inbox comparison card carrying a SERVICE offer - a differing
# vendor, the invoice's first line item and the total. This is the frame that
# proves the per-field ask reaches an entry kind that is not a fill-up. RU is
# the real test: "Поставщик", "Позиция 0" and "Итого" in the two-column
# yours-vs-receipt layout are exactly where Russian overflows.
capture RV.201-inbox-service    en -seedSettingsSignedIn -seedInboxService -inboxReset -presentScreen inbox
capture RV.201-inbox-service-ru ru -seedSettingsSignedIn -seedInboxService -inboxReset -presentScreen inbox

# RV.48: the attachment viewer's recognised page showing the parse's ASSIGNED
# fields (total/litres/price/fuel/currency) as the headline, the raw OCR lines
# demoted behind a disclosure. `-openAttachmentViewerRecognised` opens the pager
# on the second page (simctl cannot swipe). RU is where the two-column field list
# overflows worst ("Итого", "Цена/л", "Валюта", "Топливо").
capture RV.48-attachment-recognised    en -seedPhotoLocal -presentScreen editEntry -openAttachmentViewer -openAttachmentViewerRecognised
capture RV.48-attachment-recognised-ru ru -seedPhotoLocal -presentScreen editEntry -openAttachmentViewer -openAttachmentViewerRecognised

# RV.183 + RV.184: the recognised page with the CAPTURE caption
# (`Attachment.createdAt`, 10 Sep 14:32) beside the receipt's PRINTED date
# (8 Sep) in the `Date` row, and the extracted Station row. The seed's two dates
# deliberately differ, so the shot proves which one the caption reads. RU is
# where "Снято ..." plus "Заправка" plus the printed date row overflow the list.
capture RV.183-184-attachment-capture-station    en -seedPhotoCaptureVsPrinted -presentScreen editEntry -openAttachmentViewer -openAttachmentViewerRecognised
capture RV.183-184-attachment-capture-station-ru ru -seedPhotoCaptureVsPrinted -presentScreen editEntry -openAttachmentViewer -openAttachmentViewerRecognised

# RV.42: the language restart notice survives being ignored - Settings showing
# the pending notice on the Language row AFTER the picker was dismissed (the
# whole point; a shot of the picker does not demonstrate the fix). The notice is
# derived, never stored - `-languageSetPending <code>` writes a stored choice
# that differs from the running language, with the picker closed. The EN shot
# runs English with a stored Russian choice; the RU shot runs Russian with a
# stored English choice - both are pending. RU is where the notice overflows on
# a row that already carries a value and a chevron.
capture RV.42-settings-pending    en -presentScreen settings -seedSettingsGuest -languageReset -languageSetPending ru
capture RV.42-settings-pending-ru ru -presentScreen settings -seedSettingsGuest -languageReset -languageSetPending en

# The light-theme shell is the one deliberate light capture (docs/DESIGN.md).
xcrun simctl ui "${DEVICE}" appearance light >/dev/null 2>&1
capture P1.1-shell-light en -seedHomeFullHistory
xcrun simctl ui "${DEVICE}" appearance dark >/dev/null 2>&1

# RV.131: the S2 combined duplicate card shows BOTH entries it asks about - two
# rows with their time of day, odometer, total and the attachment paperclip,
# each opening its own editor. The seed's pair differs in odometer and total so
# both rows are distinguishable in frame. RU is where the longer header phrase
# and the row content could push an entry or an action below the fold.
capture RV.131-home-duplicate    en -seedSettingsSignedIn -seedHomeDuplicateFields
capture RV.131-home-duplicate-ru ru -seedSettingsSignedIn -seedHomeDuplicateFields

# RV.141: the excluded-entries footnote on Home - the count that now reaches its
# entries and says why they are out. The footnote lives below the log, so
# `-homeScrollToExcludedFootnote` (RV.141's own hook) parks Home on it; without
# it the shot is the top of Home and the subject is off-screen. RU is where
# "2 записи исключены" and its next step are tightest - and this pair is the one
# that shows whether the footnote reads as a button or as a label.
capture RV.141-home-excluded    en -seedHomeExcludedMix -homeScrollToExcludedFootnote
capture RV.141-home-excluded-ru ru -seedHomeExcludedMix -homeScrollToExcludedFootnote

# RV.142: imported stations become row titles, a blank station falls back to
# the fuel kind without repeating it, and closing fills show engine-derived
# consumption. The first two rows deliberately show both title paths in frame.
capture RV.142-log-row    en -seedHomeRV142Log
capture RV.142-log-row-ru ru -seedHomeRV142Log

# RV.144: the Edit-entry sheet after a currency edit that resolved. The seeded
# fill is the owner's imported row as the fix leaves it - the money pair was
# re-homed to the car's CURRENT home (USD) and snapshotted at rate 1 - so the
# sheet reads 2101.75 $ in the car's own dollars, never the EUR the row was
# stamped with. Signed in like the log screenshots (the log layout only
# renders with a session, PJ.3). RU is where the currency row and the
# "Liters/Price" labels run longest; the total is locale-invariant.
capture RV.144-edit-entry    en -seedSettingsSignedIn -seedHomeRV144Resolved -presentScreen editEntry
capture RV.144-edit-entry-ru ru -seedSettingsSignedIn -seedHomeRV144Resolved -presentScreen editEntry

# RV.112: a rate-pending month never prints a bare total on the vitals tile or
# the Trends series. The Home shot is the owner's exact scene (RV.140's): two
# current-month 110.00 USD rows above a month that used to read "0 €" - the
# tile is now ABSENT and the footnote + divider say why. The Trends shot is the
# RV.106 state (June/July all-pending beside a converted August): the spend
# tile prints no false figure and the pending footnote carries the phrase.
capture RV.112-home    en -seedHomeRV88USDPending
capture RV.112-home-ru ru -seedHomeRV88USDPending
# RV.140 is the SAME frame: its subject - a rate-pending Log row showing the
# ORIGINAL amount, dimmed, with the ISO code ("110.00 USD" beside the "2 entries
# pending rates" footnote) - is the log rows underneath RV.112's vitals tile in
# this very picture. RU is where the footnote count and the divider run longest;
# the amount line itself is locale-invariant.
alias_shot RV.112-home    RV.140-log-original-amount
alias_shot RV.112-home-ru RV.140-log-original-amount-ru
capture RV.112-trends    en -seedHomeRV106Pending -selectTrendsTab
capture RV.112-trends-ru ru -seedHomeRV106Pending -selectTrendsTab

# RV.166: a purchase group whose known members (30.00 EUR) share a receipt with
# a rate-pending line. The header must print the known sum MARKED with the
# pending phrase beneath it - never the bare `30.00 €` the old code printed
# while a member still waited. Signed in like the log screenshots (the log
# layout only renders with a session, PJ.3). RU is where the pending phrase
# ("1 запись ждёт курс") runs longest under the figure.
capture RV.166-home-partial-group    en -seedSettingsSignedIn -seedHomeRV166PartialGroup
capture RV.166-home-partial-group-ru ru -seedSettingsSignedIn -seedHomeRV166PartialGroup

# PJ.56: the two purchase-group headers that used to say nothing while the
# divider over them spoke. The pending pair shows an ALL-rate-pending receipt
# whose header now says "3 entries pending rates" in place of a figure (RU is
# where that phrase - "3 записи ждут курс" - runs longest under the divider's
# identical sentence); the mixed pair shows a receipt whose known lines span
# home currencies (EUR + USD), whose header now states the per-currency
# breakdown exactly as the divider above it does - never a summed total.
capture PJ.56-home-pending-group    en -seedSettingsSignedIn -seedHomePJ56PendingGroup
capture PJ.56-home-pending-group-ru ru -seedSettingsSignedIn -seedHomePJ56PendingGroup
capture PJ.56-home-mixed-group    en -seedSettingsSignedIn -seedHomePJ56MixedGroup
capture PJ.56-home-mixed-group-ru ru -seedSettingsSignedIn -seedHomePJ56MixedGroup

# RV.160: a send acknowledges itself - the composer collapses into a
# confirmation panel where the form's top was, so the confirmation is visible
# at About's top scroll with no tap needed (`-feedbackAutoSend` + the transport
# seam reach the terminal state; `simctl` cannot tap). The sent pose shows the
# `.sent` outcome (202), the offline pose the queued-outcome reassurance
# ("Saved – ...") - the copy that must never read as a failure. RU is where the
# panel copy runs longest ("Сохранено – отправится автоматически, когда
# появится связь.").
# RV.159: the two consents, drawn as different kinds of object. The frame must
# hold BOTH - the optional "Attach diagnostics" card above, and the gating
# consent below it under its own "Before you send" eyebrow - because the defect
# was that the two were indistinguishable, and a shot of either one alone
# proves nothing. `-diagnosticsConsentOn` puts the optional one in its ON state
# (where it used to look most like the gate) while `-feedbackConsentReset`
# leaves the gate OFF at its default. The XL pair is the overflow check: a
# RU runs 20-30% longer than EN, so its gate label is the one that clips.
# There is NO XL capture here, deliberately: About has no scroll hook, and at
# XL the gate sits entirely below the fold - the frame would show the eyebrow
# clipped at the edge and none of the control it heads, which is a confident
# picture of nothing (the P1.5-log-stream failure). The XL claim is covered by
# `testRV159ConsentBlockRendersAtXLInEnglish/InRussian`, which assert the frames
# directly. An About scroll hook would make the shot possible - filed as RV.175.
capture RV.159-about-consents        en -presentScreen about -feedbackConsentReset -diagnosticsConsentOn
capture RV.159-about-consents-ru     ru -presentScreen about -feedbackConsentReset -diagnosticsConsentOn

capture RV.160-about-feedback-sent       en -feedbackConsentOn -feedbackTransportSuccess -feedbackAutoSend -presentScreen about
capture RV.160-about-feedback-sent-ru    ru -feedbackConsentOn -feedbackTransportSuccess -feedbackAutoSend -presentScreen about
capture RV.160-about-feedback-offline    en -feedbackConsentOn -feedbackTransportOffline -feedbackAutoSend -presentScreen about
capture RV.160-about-feedback-offline-ru ru -feedbackConsentOn -feedbackTransportOffline -feedbackAutoSend -presentScreen about

# PJ.55: the per-station favourite control on RV.150's Station settings screen.
capture PJ.55-station-favourite    en -seedStationSettings -presentScreen stationSettings
capture PJ.55-station-favourite-ru ru -seedStationSettings -presentScreen stationSettings

# Two names for one picture is a defect this file produced ten times before
# anyone counted (see alias_shot). A deliberate alias is a copy and is expected;
# anything else identical means two capture lines are shooting the same frame -
# collapse one into an alias_shot rather than paying for the launch and letting
# the pair drift. Only frames captured in THIS run are compared.
if [ "${#CAPTURED[@]}" -gt 1 ]; then
    echo
    echo "checking for capture lines that shot the same frame..."
    dupes="$(for name in "${CAPTURED[@]}"; do
                 [ -f "${OUT}/${name}.png" ] && echo "$(md5 -q "${OUT}/${name}.png") ${name}"
             done | sort | awk '{ if ($1 == prev) { print "  " prevname " == " $2 } prev = $1; prevname = $2 }')"
    if [ -n "${dupes}" ]; then
        echo "${dupes}"
        echo "  ^ identical frames under different names - make one an alias_shot." >&2
    else
        echo "  none - every capture line produced its own frame."
    fi
fi

# RV.177: the home-currency question as a SHEET with a real hierarchy - the
# irreversible "Convert the log" filled in taillight, the harmless "Keep the
# entries as they are" quiet. It replaced a system alert whose two buttons were
# both accent-tinted and therefore identical (RV.152's frames, retired in the
# same change). `-presentCurrencyChangePrompt` raises it over Vehicle detail;
# `-presentScreen vehicleDetail` is NOT optional - without it the capture
# photographs the Log and looks like a success. RU is where the warning grows a
# line and pushes the actions down.
capture RV.177-home-currency-change    en -seedHomeRV152 -presentScreen vehicleDetail -presentCurrencyChangePrompt
capture RV.177-home-currency-change-ru ru -seedHomeRV152 -presentScreen vehicleDetail -presentCurrencyChangePrompt


# RV.176: the audit's gap closure. Every frame below was committed with no
# capture line - a screenshot nobody could regenerate. Each one now has a line,
# reconstructed from its task's own DEBUG seed, so a shared change can be
# re-shot instead of silently invalidating the record. `P1.1-shell-dark-
# rejected-accent-tabbar` is the one deliberate exception: it is the record of a
# hard-rule-5 violation the code no longer produces, and is a `legacy` manifest
# entry rather than a line. The app-icon exports and the notification banner
# frames were deleted: neither is a screen the capture script can produce.
capture OB.3-settings-last-failure                       en -presentScreen settings -seedSettingsLastFailure
capture OB.3-settings-last-failure-ru                    ru -presentScreen settings -seedSettingsLastFailure
capture OB.3-settings-restored                           en -presentScreen settings -seedSettingsRestoredSync
capture OB.3-settings-restored-ru                        ru -presentScreen settings -seedSettingsRestoredSync
capture OB.4-about-diagnostics                           en -presentScreen about -seedDiagnosticsData
capture OB.4-about-diagnostics-ru                        ru -presentScreen about -seedDiagnosticsData
capture OB.4-diagnostics-preview                         en -presentScreen about -diagnosticsAutoOpenPreview -seedDiagnosticsData
capture OB.4-diagnostics-preview-ru                      ru -presentScreen about -diagnosticsAutoOpenPreview -seedDiagnosticsData
capture P1.13-confirm-odometer                           en -seedVehicleForUITests -presentScreen confirmManual -screenshotOdometer 123600
capture P1.13-confirm-odometer-ru                        ru -seedVehicleForUITests -presentScreen confirmManual -screenshotOdometer 123600
capture P1.13b-conflict-quote-ru                         ru -seedVehicleForUITests -presentScreen confirmManual -screenshotOdometer 121727
alias_shot PJ.4-home-reminder P5.3-home-banner-en
capture P5.3-home-banner-en-xl                           en -seedSettingsSignedIn -seedHomeReminderDue -UIPreferredContentSizeCategoryName UICTContentSizeCategoryXL
alias_shot PJ.4-home-reminder-ru P5.3-home-banner-ru
capture P5.3-home-banner-ru-xl                           ru -seedSettingsSignedIn -seedHomeReminderDue -UIPreferredContentSizeCategoryName UICTContentSizeCategoryXL
alias_shot P3.2-service-link P5.3-parts-link-en
alias_shot P3.2-service-link-ru P5.3-parts-link-ru
capture P5.3-parts-link-ru-xl                            ru -seedServiceEntryLink -presentScreen serviceEntry -UIPreferredContentSizeCategoryName UICTContentSizeCategoryXL
alias_shot P1.7-recently-deleted P5.3-recently-deleted-en
alias_shot P1.7-recently-deleted-ru P5.3-recently-deleted-ru
alias_shot P4.4-wrong-provider P5.3-signin-wrong-provider-en
alias_shot P4.4-wrong-provider-ru P5.3-signin-wrong-provider-ru
capture P5.5b-import-review-ru-xl                        ru -presentScreen importWizard -importStubParse review -seedImportReview -UIPreferredContentSizeCategoryName UICTContentSizeCategoryXL
capture P6.13-home-xl                                    en -seedHomeFullHistory -UIPreferredContentSizeCategoryName UICTContentSizeCategoryXL
capture P6.13-home-xl-ru                                 ru -seedHomeFullHistory -UIPreferredContentSizeCategoryName UICTContentSizeCategoryXL
alias_shot P6.1b-insight-dismiss P6.17-anomaly-dismiss
alias_shot P6.1b-insight-dismiss-ru P6.17-anomaly-dismiss-ru
alias_shot P1.4-home P6.5-home-log
alias_shot P1.4-home-ru P6.5-home-log-ru
alias_shot P1.7-recently-deleted P6.5-recently-deleted
alias_shot P1.7-recently-deleted-ru P6.5-recently-deleted-ru
alias_shot P2.1-capture PJ.1-capture
alias_shot P2.1-capture-ru PJ.1-capture-ru
alias_shot PJ.12-capture-ev PJ.12b-capture-ev
alias_shot PJ.12-capture-ev-ru PJ.12b-capture-ev-ru
capture PJ.12b-capture-ice                               en -presentScreen capture -cameraStatus authorized -powertrain ice
capture PJ.12b-capture-ice-ru                            ru -presentScreen capture -cameraStatus authorized -powertrain ice
capture PJ.17b-empty-scan-caption                        en -seedVehicleForUITests -presentScreen confirmManual -seedConfirmPrefillEmpty
alias_shot P2.3-confirm-empty-ru PJ.17b-empty-scan-caption-ru
alias_shot P1.3-confirm-manual PJ.19-nostation
alias_shot P1.3-confirm-manual-ru PJ.19-nostation-ru
capture PJ.19-station                                    en -seedVehicleForUITests -presentScreen confirmManual -seedStationSuggestion
capture PJ.19-station-ru                                 ru -seedVehicleForUITests -presentScreen confirmManual -seedStationSuggestion
alias_shot RV.141-home-excluded PJ.57-home-excluded-link
alias_shot RV.141-home-excluded-ru PJ.57-home-excluded-link-ru
capture PR.1-settings-auth-expired                       en -presentScreen settings -seedSettingsAuthExpired
capture PR.1-settings-auth-expired-ru                    ru -presentScreen settings -seedSettingsAuthExpired
capture PR.13-settings-offline                           en -presentScreen settings -seedSettingsServerDown -importTransportOffline
capture PR.13-settings-offline-ru                        ru -presentScreen settings -seedSettingsServerDown -importTransportOffline
capture PR.13-settings-server-down                       en -presentScreen settings -seedSettingsServerDown
capture PR.13-settings-server-down-ru                    ru -presentScreen settings -seedSettingsServerDown
capture PR.14-changed-by-sync                            en -seedEditEntrySyncOverwritten -presentScreen editEntry
capture PR.14-changed-by-sync-ru                         ru -seedEditEntrySyncOverwritten -presentScreen editEntry
capture PR.14-synced-toast                               en -seedSettingsSynced -forceSyncToast
capture PR.14-synced-toast-ru                            ru -seedSettingsSynced -forceSyncToast
capture RV.100-home-zero-car                             en -seedHomeDeleteLastCar
capture RV.100-home-zero-car-ru                          ru -seedHomeDeleteLastCar
capture RV.103-log-more                                  en -seedHomeRV103LongLog -homeScrollLogReveal
capture RV.103-log-more-ru                               ru -seedHomeRV103LongLog -homeScrollLogReveal
capture RV.106-log-pending-month                         en -seedSettingsSignedIn -seedHomeRV106Pending
capture RV.106-log-pending-month-ru                      ru -seedSettingsSignedIn -seedHomeRV106Pending
capture RV.116-import-unsupported-notice                 en -presentScreen importWizard -importStubFormats unsupported -importStubParse unsupported -seedImportUnsupported
capture RV.116-import-unsupported-notice-ru              ru -presentScreen importWizard -importStubFormats unsupported -importStubParse unsupported -seedImportUnsupported
alias_shot RV.66-flagged-list RV.117b-flagged
alias_shot RV.66-flagged-list-ru RV.117b-flagged-ru
capture RV.117b-neighbourhood                            en -seedEditEntryConflictMiddle -presentScreen editEntry -scrollToNeighbourhood
capture RV.117b-neighbourhood-ru                         ru -seedEditEntryConflictMiddle -presentScreen editEntry -scrollToNeighbourhood
alias_shot P6.1b-insight-evidence RV.121-home-anomaly
alias_shot P6.1b-insight-evidence-ru RV.121-home-anomaly-ru
capture RV.126-confirm-conflict                          en -seedVehicleMiles -presentScreen confirmManual -screenshotOdometer 119486
capture RV.126-confirm-conflict-ru                       ru -seedVehicleMiles -presentScreen confirmManual -screenshotOdometer 119486
capture RV.137-vehicle-edit                              en -seedHomeCarSwitcher -presentScreen vehicleDetail -vehicleDetailModelSuggestions -vehicleDetailKeyboardUp
capture RV.137-vehicle-edit-chips                        en -seedHomeCarSwitcher -presentScreen vehicleDetail -vehicleDetailKeyboardUp
capture RV.137-vehicle-edit-chips-ru                     ru -seedHomeCarSwitcher -presentScreen vehicleDetail -vehicleDetailKeyboardUp
capture RV.137-vehicle-edit-ru                           ru -seedHomeCarSwitcher -presentScreen vehicleDetail -vehicleDetailModelSuggestions -vehicleDetailKeyboardUp
capture RV.182-catalog-fill-tank                         en -seedHomeCarSwitcher -presentScreen vehicleDetail -vehicleDetailCatalogFillLitres -scrollToAccuracy
capture RV.182-catalog-fill-tank-ru                      ru -seedHomeCarSwitcher -presentScreen vehicleDetail -vehicleDetailCatalogFillLitres -scrollToAccuracy
capture RV.182-catalog-fill-tank-gal                     en -seedHomeCarSwitcher -presentScreen vehicleDetail -vehicleDetailCatalogFillGallons -scrollToAccuracy
capture RV.182-catalog-fill-tank-gal-ru                  ru -seedHomeCarSwitcher -presentScreen vehicleDetail -vehicleDetailCatalogFillGallons -scrollToAccuracy
capture RV.141-excluded-list                             en -seedHomeExcludedMix -presentScreen excludedEntries
capture RV.141-excluded-list-ru                          ru -seedHomeExcludedMix -presentScreen excludedEntries
capture RV.141-home                                      en -seedHomeExcludedMix
capture RV.141-home-ru                                   ru -seedHomeExcludedMix
capture RV.145-log                                       en -seedSettingsSignedIn -seedHomeRV145Owner
capture RV.145-log-ru                                    ru -seedSettingsSignedIn -seedHomeRV145Owner
capture RV.145-trends                                    en -seedSettingsSignedIn -seedHomeRV145Owner -selectTrendsTab
capture RV.145-trends-ru                                 ru -seedSettingsSignedIn -seedHomeRV145Owner -selectTrendsTab
capture RV.146-currency                                  en -seedVehicleForUITests -presentScreen confirmManual -seedConfirmForeignLowConfidence
capture RV.146-currency-ru                               ru -seedVehicleForUITests -presentScreen confirmManual -seedConfirmForeignLowConfidence
capture RV.147-trends                                    en -seedSettingsSignedIn -seedHomeRV147Pending -selectTrendsTab
capture RV.147-trends-ru                                 ru -seedSettingsSignedIn -seedHomeRV147Pending -selectTrendsTab
alias_shot PJ.55-station-favourite RV.150-station
alias_shot PJ.55-station-favourite-ru RV.150-station-ru
alias_shot P1.3-confirm-manual RV.156-station-add
alias_shot P1.3-confirm-manual-ru RV.156-station-add-ru
capture RV.156-station-created                           en -seedVehicleForUITests -presentScreen confirmManual -seedStationRowSelected
capture RV.156-station-created-ru                        ru -seedVehicleForUITests -presentScreen confirmManual -seedStationRowSelected
capture RV.161-confirm-station                           en -seedVehicleForUITests -presentScreen confirmManual -seedConfirmPrefillStation
capture RV.161-confirm-station-ru                        ru -seedVehicleForUITests -presentScreen confirmManual -seedConfirmPrefillStation
capture RV.17-downloading                                en -seedPhotoRemote -seedBlobFetchDelay 30 -presentScreen editEntry -openAttachmentViewer
capture RV.17-downloading-ru                             ru -seedPhotoRemote -seedBlobFetchDelay 30 -presentScreen editEntry -openAttachmentViewer
alias_shot RV.48-attachment-recognised RV.17-recognised
alias_shot RV.48-attachment-recognised-ru RV.17-recognised-ru
capture RV.21-garage                                     en -seedSettingsSignedIn -seedHomeFullHistory -selectGarageTab
capture RV.21-garage-ru                                  ru -seedSettingsSignedIn -seedHomeFullHistory -selectGarageTab
capture RV.21-log                                        en -seedSettingsSignedIn -seedHomeFullHistory
capture RV.21-log-ru                                     ru -seedSettingsSignedIn -seedHomeFullHistory
capture RV.21-trends                                     en -seedSettingsSignedIn -seedHomeFullHistory -selectTrendsTab
capture RV.21-trends-ru                                  ru -seedSettingsSignedIn -seedHomeFullHistory -selectTrendsTab
capture RV.28-fuel-chips                                 en -seedVehiclePetrolLPG -presentScreen confirmManual -screenshotPrefill
capture RV.28-fuel-chips-ru                              ru -seedVehiclePetrolLPG -presentScreen confirmManual -screenshotPrefill
capture RV.37-replace-ask                                en -seedPhotoLocal -presentScreen editEntry -openAttachmentViewer -openAttachmentViewerReplaceAsk
capture RV.37-replace-ask-ru                             ru -seedPhotoLocal -presentScreen editEntry -openAttachmentViewer -openAttachmentViewerReplaceAsk
alias_shot P4.9b-settings-synced RV.40-settings-signout
alias_shot P4.9b-settings-synced-ru RV.40-settings-signout-ru
capture RV.54-account-devices                            en -presentScreen settings -seedSettingsDeviceCount
capture RV.54-account-devices-ru                         ru -presentScreen settings -seedSettingsDeviceCount
capture RV.57-capture-prefill                            en -seedFillUpScan -presentScreen capture -cameraStatus authorized
capture RV.57-capture-prefill-ru                         ru -seedFillUpScan -presentScreen capture -cameraStatus authorized
capture RV.58-settings-revoked                           en -presentScreen settings -seedSettingsRevoked410
capture RV.58-settings-revoked-ru                        ru -presentScreen settings -seedSettingsRevoked410
alias_shot P1.4-home-empty RV.61-home-typeit
alias_shot P1.4-home-empty-ru RV.61-home-typeit-ru
capture RV.62-expense-prefill                            en -seedExpenseEntryPrefill -presentScreen serviceEntry
capture RV.62-expense-prefill-ru                         ru -seedExpenseEntryPrefill -presentScreen serviceEntry
# RV.200: an Expense-mode scan of a parking ticket lands the expense form with
# the inferred category PRESELECTED (Parking / Парковка) and editable, beside
# the amount it also read. The recognition is seeded but the CATEGORY is not:
# `-seedExpenseScanParking` hands the real inference the ticket's OCR lines, so
# the frame shows the shipped vocabulary's answer. `-captureAutoUse` accepts the
# RV.5 review without a tap (`simctl` cannot tap).
capture RV.200-expense-category                          en -seedVehicleForUITests -presentScreen capture -cameraStatus authorized -captureMode expense -captureFixtureImage "${RV5_FIXTURE}" -seedExpenseScanParking -captureAutoUse
capture RV.200-expense-category-ru                       ru -seedVehicleForUITests -presentScreen capture -cameraStatus authorized -captureMode expense -captureFixtureImage "${RV5_FIXTURE}" -seedExpenseScanParking -captureAutoUse

# RV.219: the fiscal QR's timestamp is the authoritative date (docs/SCHEMA.md ->
# FISCAL QR, docs/JOURNEYS.md J5/F5). receipt-010's QR decodes but OCR reads no
# printed date, so the Confirm form's date row is the frame that proves the QR
# date landed - it must read 25 Nov 2024, not the form default. `-captureAutoUse`
# accepts the RV.5 review without a tap (`simctl` cannot tap). RU is the real
# test: the date row's month abbreviation and its "Date"/"Дата" eyebrow are where
# the 20-30% expansion lands.
RV219_FIXTURE="$PWD/Spike/ReceiptSpike/fixtures/receipts/receipt-010-gazpromneft-diesel-bonus-ru.jpeg"
capture RV.219-qr-date                                   en -seedVehicleForUITests -presentScreen capture -cameraStatus authorized -captureFixtureImage "${RV219_FIXTURE}" -captureAutoUse
capture RV.219-qr-date-ru                                ru -seedVehicleForUITests -presentScreen capture -cameraStatus authorized -captureFixtureImage "${RV219_FIXTURE}" -captureAutoUse
capture RV.64-inbox-noticks                              en -seedInboxItem -inboxReset -presentScreen inbox
capture RV.64-inbox-noticks-ru                           ru -seedInboxItem -inboxReset -presentScreen inbox
capture RV.64-inbox-ticked                               en -seedInboxItem -inboxReset -presentScreen inbox -inboxScreenshotTick
capture RV.64-inbox-ticked-ru                            ru -seedInboxItem -inboxReset -presentScreen inbox -inboxScreenshotTick
capture RV.65-confirm-auth-notice                        en -seedVehicleForUITests -presentScreen confirmManual -seedConfirmPrefillLocked -seedGatewayAuthExpired
capture RV.65-confirm-auth-notice-ru                     ru -seedVehicleForUITests -presentScreen confirmManual -seedConfirmPrefillLocked -seedGatewayAuthExpired
capture RV.66-chip-home                                  en -seedHomeRV66TwoCar -seedSyncFlaggedBatch
capture RV.66-chip-home-ru                               ru -seedHomeRV66TwoCar -seedSyncFlaggedBatch
capture RV.66-flagged-list                               en -seedSettingsSignedIn -seedSettingsFlaggedNeighbourhood -presentScreen inbox
capture RV.66-flagged-list-ru                            ru -seedSettingsSignedIn -seedSettingsFlaggedNeighbourhood -presentScreen inbox
capture RV.67-addcar-suggestions                         en -presentScreen addVehicle -addVehicleModelSuggestions
capture RV.67-addcar-suggestions-ru                      ru -presentScreen addVehicle -addVehicleModelSuggestions
capture RV.69-addcar-units                               en -presentScreen addVehicle -addVehicleModelSuggestions -seedVehicleMiles
capture RV.69-addcar-units-ru                            ru -presentScreen addVehicle -addVehicleModelSuggestions -seedVehicleMiles
alias_shot P4.9b-settings-quota RV.70-quota-card
alias_shot P4.9b-settings-quota-ru RV.70-quota-card-ru
alias_shot P4.9b-settings-guest RV.70-settings
alias_shot P4.9b-settings-guest-ru RV.70-settings-ru
capture RV.71-confirm-fuel-mismatch                      en -seedVehicleForUITests -presentScreen confirmManual -seedConfirmPrefillFuelMismatch
capture RV.71-confirm-fuel-mismatch-ru                   ru -seedVehicleForUITests -presentScreen confirmManual -seedConfirmPrefillFuelMismatch
capture RV.73-import-read-failed                         en -presentScreen importWizard -importStubFormats shipped -seedImportReadFailed
capture RV.73-import-read-failed-ru                      ru -presentScreen importWizard -importStubFormats shipped -seedImportReadFailed
capture RV.74-reminders-deeplink                         en -seedRemindersDeepLink -presentScreen reminders
capture RV.74-reminders-deeplink-ru                      ru -seedRemindersDeepLink -presentScreen reminders
capture RV.75-reminder-form-car-empty                    en -seedReminderForm -presentScreen reminderForm
capture RV.75-reminder-form-car-empty-ru                 ru -seedReminderForm -presentScreen reminderForm
capture RV.75-reminders-all                              en -seedRemindersAll -presentScreen reminders
capture RV.75-reminders-all-ru                           ru -seedRemindersAll -presentScreen reminders
alias_shot P3.4-reminders-empty RV.76-reminders-empty
alias_shot P3.4-reminders-empty-ru RV.76-reminders-empty-ru
alias_shot P3.4-reminders RV.76-reminders-entry
alias_shot P3.4-reminders-ru RV.76-reminders-entry-ru
capture RV.77-service-reminder-offer                     en -seedServiceReminderOffer -presentScreen serviceEntry -presentServiceReminderOffer
capture RV.77-service-reminder-offer-ru                  ru -seedServiceReminderOffer -presentScreen serviceEntry -presentServiceReminderOffer
capture RV.79-car-switcher-counts                        en -seedHomeGarageCounts -presentScreen carSwitcher
capture RV.79-car-switcher-counts-ru                     ru -seedHomeGarageCounts -presentScreen carSwitcher
capture RV.79-garage-counts                              en -seedHomeGarageCounts -selectGarageTab
capture RV.79-garage-counts-ru                           ru -seedHomeGarageCounts -selectGarageTab
capture RV.8-confirm-cloud-reading                       en -seedVehicleForUITests -presentScreen confirmManual -seedGateway -seedGatewayConsistent
capture RV.8-confirm-cloud-reading-ru                    ru -seedVehicleForUITests -presentScreen confirmManual -seedGateway -seedGatewayConsistent
alias_shot P5.5b-import-source RV.80-import-not-supported
alias_shot P5.5b-import-source-ru RV.80-import-not-supported-ru
capture RV.81-vehicle-detail-archived                    en -presentArchivedVehicleDetail -presentScreen vehicleDetail
capture RV.81-vehicle-detail-archived-ru                 ru -presentArchivedVehicleDetail -presentScreen vehicleDetail
alias_shot RV.79-garage-counts RV.83-garage-attention
alias_shot RV.79-garage-counts-ru RV.83-garage-attention-ru
capture RV.84-import-422                                 en -presentScreen importWizard -importStubFormats shipped -importStubParse422 -seedImportParse422
capture RV.84-import-422-ru                              ru -presentScreen importWizard -importStubFormats shipped -importStubParse422 -seedImportParse422
alias_shot P5.5b-import-source RV.84-import-not-supported
alias_shot P5.5b-import-source-ru RV.84-import-not-supported-ru
capture RV.85-import-preview-resolved-dates              en -presentScreen importWizard -importStubParse mfm -seedImportResolvedDates
capture RV.85-import-preview-resolved-dates-ru           ru -presentScreen importWizard -importStubParse mfm -seedImportResolvedDates
capture RV.88-home-imported-usd-converted                en -seedSettingsSignedIn -seedHomeRV88USDConverted
capture RV.88-home-imported-usd-converted-ru             ru -seedSettingsSignedIn -seedHomeRV88USDConverted
capture RV.88-home-imported-usd-pending                  en -seedSettingsSignedIn -seedHomeRV88USDPending
capture RV.88-home-imported-usd-pending-ru               ru -seedSettingsSignedIn -seedHomeRV88USDPending
capture RV.89-log-multiyear                              en -seedSettingsSignedIn -seedHomeMultiYearLog
capture RV.89-log-multiyear-ru                           ru -seedSettingsSignedIn -seedHomeMultiYearLog
capture RV.9-attachment-not-downloaded                   en -seedPhotoRemote -presentScreen editEntry -openAttachmentViewer
capture RV.9-attachment-not-downloaded-ru                ru -seedPhotoRemote -presentScreen editEntry -openAttachmentViewer
capture RV.9-attachment-viewer                           en -seedPhotoLocal -presentScreen editEntry -openAttachmentViewer
capture RV.9-attachment-viewer-ru                        ru -seedPhotoLocal -presentScreen editEntry -openAttachmentViewer
alias_shot P1.7-recently-deleted RV.98-recently-deleted
alias_shot P1.7-recently-deleted-ru RV.98-recently-deleted-ru
capture RV.99-vehicle-detail-delete-confirm              en -seedHome -presentScreen vehicleDetail -presentVehicleDeleteConfirm
capture RV.99-vehicle-detail-delete-confirm-ru           ru -seedHome -presentScreen vehicleDetail -presentVehicleDeleteConfirm
capture RV86-cars-ask                                    en -presentScreen importWizard -importStubFormats shipped -seedImportCars
capture RV86-cars-ask-ru                                 ru -presentScreen importWizard -importStubFormats shipped -seedImportCars
capture RV86-cars-decided                                en -presentScreen importWizard -importStubFormats shipped -seedImportCarsDecided
capture RV86-cars-decided-ru                             ru -presentScreen importWizard -importStubFormats shipped -seedImportCarsDecided
alias_shot P4.4-sign-in SH.4-sign-in-google-en
alias_shot P4.4-sign-in-ru SH.4-sign-in-google-ru

# Merge this run's frames into the manifest. `frames` is the script's record;
# `legacy` (frames no line can reproduce) is hand-maintained and preserved.
if [ "${#CAPTURED[@]}" -gt 0 ]; then
    python3 scripts/screenshot-manifest.py merge "${MANIFEST}" "${MANIFEST_TSV}"
fi
rm -f "${MANIFEST_TSV}"

echo
echo "Done. NOW OPEN THEM - this script proves a file was written, not that it"
echo "shows the intended screen. A wrong seed renders an empty or error state"
echo "that looks like a successful capture from here."
