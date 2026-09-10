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

# RV.48: the attachment viewer's recognised page showing the parse's ASSIGNED
# fields (total/litres/price/fuel/currency) as the headline, the raw OCR lines
# demoted behind a disclosure. `-openAttachmentViewerRecognised` opens the pager
# on the second page (simctl cannot swipe). RU is where the two-column field list
# overflows worst ("Итого", "Цена/л", "Валюта", "Топливо").
capture RV.48-attachment-recognised    en -seedPhotoLocal -presentScreen editEntry -openAttachmentViewer -openAttachmentViewerRecognised
capture RV.48-attachment-recognised-ru ru -seedPhotoLocal -presentScreen editEntry -openAttachmentViewer -openAttachmentViewerRecognised

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

echo
echo "Done. NOW OPEN THEM - this script proves a file was written, not that it"
echo "shows the intended screen. A wrong seed renders an empty or error state"
echo "that looks like a successful capture from here."
