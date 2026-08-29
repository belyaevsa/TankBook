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
capture() {
    local name="$1" lang="$2"; shift 2
    local path="${OUT}/${name}.png"
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

# P5.2b: the rate-pending card's missing next step (the manual-rate row on the
# card itself, hard rule 7), the same card flipped to converted from a manual
# rate (source "Manual"), and the F9 "N entries pending rates" footnote on
# Trends and Home. RU is where "Изменить курс" and "N записей ждут курс" are
# tightest.
capture P5.2b-confirm-pending-next-step     en -seedVehicleForUITests -presentScreen confirmManual -seedConfirmForeignPending
capture P5.2b-confirm-pending-next-step-ru  ru -seedVehicleForUITests -presentScreen confirmManual -seedConfirmForeignPending
capture P5.2b-confirm-manual-rate           en -seedVehicleForUITests -presentScreen confirmManual -seedConfirmForeignPending -manualRate 4.2706
capture P5.2b-confirm-manual-rate-ru        ru -seedVehicleForUITests -presentScreen confirmManual -seedConfirmForeignPending -manualRate 4.2706
capture P5.2b-trends-pending-footnote       en -seedHomePendingRates -selectTrendsTab
capture P5.2b-trends-pending-footnote-ru    ru -seedHomePendingRates -selectTrendsTab
capture P5.2b-home-pending-footnote         en -seedHomePendingRates
capture P5.2b-home-pending-footnote-ru      ru -seedHomePendingRates

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

# P3.4: the Reminders list (attention + scheduled groups), the empty state,
# and the reminder form. RU is where the trailing chip ("12 дней") and the
# section labels ("ТРЕБУЕТ ВНИМАНИЯ") are tightest.
capture P3.4-reminders            en -seedReminders -presentScreen reminders
capture P3.4-reminders-ru         ru -seedReminders -presentScreen reminders
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
# shape that overflows.
capture P4.4-sign-in              en -presentScreen signIn
capture P4.4-sign-in-ru           ru -presentScreen signIn
capture P4.4-wrong-provider       en -presentScreen signIn -signInWrongProvider
capture P4.4-wrong-provider-ru    ru -presentScreen signIn -signInWrongProvider

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

# P5.5b: the import wizard's three screens (source picker, preview gate, review
# list) plus the per-car export row on Vehicle detail. The picker renders the
# stub transport's list; the preview/review install a stub parse (no file
# picker, no server). RU is where the longest copy overflows - the review intro
# is a two-count sentence and the duplicate warning is a paragraph.
capture P5.5b-import-source     en -presentScreen importWizard -importStubFormats one
capture P5.5b-import-source-ru  ru -presentScreen importWizard -importStubFormats one
capture P5.5b-import-preview    en -presentScreen importWizard -importStubParse mfm -seedImportPreview
capture P5.5b-import-preview-ru ru -presentScreen importWizard -importStubParse mfm -seedImportPreview
capture P5.5b-import-review     en -presentScreen importWizard -importStubParse review -seedImportReview
capture P5.5b-import-review-ru  ru -presentScreen importWizard -importStubParse review -seedImportReview
capture P5.5b-export            en -seedHomeCarSwitcher -presentScreen vehicleDetail
capture P5.5b-export-ru         ru -seedHomeCarSwitcher -presentScreen vehicleDetail

# PJ.10/PJ.9: the preview's once-per-file date-format question (confirm stays
# disabled until answered) and the review list's non-fuel row with its
# "Import as service" action. The service seed's review screen holds exactly
# one service row, so the action is in frame without scrolling.
capture PJ.10-import-date-question     en -presentScreen importWizard -importStubParse mfm -seedImportPreview
capture PJ.10-import-date-question-ru  ru -presentScreen importWizard -importStubParse mfm -seedImportPreview
capture PJ.9-import-nonfuel-row        en -presentScreen importWizard -importStubFormats one -seedImportService
capture PJ.9-import-nonfuel-row-ru     ru -presentScreen importWizard -importStubFormats one -seedImportService

# The light-theme shell is the one deliberate light capture (docs/DESIGN.md).
xcrun simctl ui "${DEVICE}" appearance light >/dev/null 2>&1
capture P1.1-shell-light en -seedHomeFullHistory
xcrun simctl ui "${DEVICE}" appearance dark >/dev/null 2>&1

echo
echo "Done. NOW OPEN THEM - this script proves a file was written, not that it"
echo "shows the intended screen. A wrong seed renders an empty or error state"
echo "that looks like a successful capture from here."
