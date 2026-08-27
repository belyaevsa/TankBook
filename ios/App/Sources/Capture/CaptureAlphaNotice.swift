import SwiftUI
import TankbookCore

/// The P6.10 alpha-testing disclosure on the capture surface
/// (docs/ERRORS.md -> Capture -> Alpha notice). It is a **disclosure, not an
/// error**: passive `inkSoft` like `PendingRatesFootnote`, never `warn` amber,
/// and it carries no next-step action bar - there is nothing to fix, the ask is
/// simply to keep capturing (hard rule 15 - this notice must never frame
/// scanning as the failure branch).
///
/// Lifecycle (decided P6.10, recorded in docs/ERRORS.md and docs/SCREENMAP.md):
/// - **Placement**: the live camera surface, directly above the shutter - the
///   last thing read before the shutter is pressed. It is never on a Confirm
///   sheet, never on the manual form, and never between shutter and result (it
///   is a static part of the surface, so nothing can appear mid-capture).
/// - **Dismissal**: a tap on the × hides it for the rest of the calendar day,
///   persisted in UserDefaults (a relaunch the same day stays dismissed).
/// - **Retirement**: it stops appearing once the device has logged **3
///   captures** (any entry, across all live vehicles) **or** the notice has
///   been dismissed on **3 separate days**, whichever comes first. 3 is the
///   app's own experience threshold (the floor-3 consumption model treats three
///   fill-ups as "enough data"): after three captures the user judges
///   recognition from their own scans, and after three dismissals further
///   repetition is a nag, not teaching.
/// - **The "send us a case" path is deliberately not wired into the notice**:
///   rule 5 forbids an action bar on a non-error, and the one place feedback
///   lives already exists - About & feedback (`POST /feedback`, docs/API.md),
///   reachable from Settings. The notice's whole point is to keep captures
///   coming; a scan that goes wrong is a case for that screen.
struct CaptureAlphaNotice: View {
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("Recognition is in alpha testing – it can't get every field right yet. Your captures improve it, so keep them coming and bear with mistakes.")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Got it")
            .accessibilityIdentifier("captureAlphaNoticeDismissButton")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("captureAlphaNotice")
    }
}

/// The notice's lifecycle state. Purely UserDefaults + a capture count; nothing
/// here touches the network, so the disclosure is as local-first as capture
/// itself (hard rule 1).
enum CaptureAlphaNoticeState {
    static let dismissedAtKey = "capture.alphaNoticeDismissedAt"
    static let dismissCountKey = "capture.alphaNoticeDismissCount"

    /// The experience threshold shared with the floor-3 consumption model
    /// (docs/SCHEMA.md -> consumption): three captures is "enough first-hand
    /// data" for the notice to retire.
    static let retirementThreshold = 3

    static func dismissCount() -> Int {
        UserDefaults.standard.integer(forKey: dismissCountKey)
    }

    static func dismissedToday(now: Date = Date()) -> Bool {
        guard let date = UserDefaults.standard.object(forKey: dismissedAtKey) as? Date else {
            return false
        }
        return Calendar.current.isDate(date, inSameDayAs: now)
    }

    /// Retired when the user has either logged three captures (they judge
    /// recognition from experience now) or dismissed the notice on three
    /// separate days (they have read it three times; repetition is a nag).
    static func isRetired(captureCount: Int) -> Bool {
        captureCount >= retirementThreshold || dismissCount() >= retirementThreshold
    }

    static func shouldShow(captureCount: Int, now: Date = Date()) -> Bool {
        guard !isRetired(captureCount: captureCount) else { return false }
        return !dismissedToday(now: now)
    }

    /// The × was tapped: hide for the rest of the day and count the dismissal.
    static func dismiss() {
        UserDefaults.standard.set(Date(), forKey: dismissedAtKey)
        UserDefaults.standard.set(dismissCount() + 1, forKey: dismissCountKey)
    }

    /// Test-only hooks (same pattern as `-cameraStatus`): `-alphaNoticeReset`
    /// clears the state so each UI test starts from the same place, and
    /// `-alphaNoticeDismissCount <n>` seeds a dismissal history so the
    /// three-dismissal retirement is reachable without waiting three days.
    static func resetForTestsIfRequested(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        if arguments.contains("-alphaNoticeReset") {
            UserDefaults.standard.removeObject(forKey: dismissedAtKey)
            UserDefaults.standard.removeObject(forKey: dismissCountKey)
        }
        if let index = arguments.firstIndex(of: "-alphaNoticeDismissCount"),
           arguments.indices.contains(index + 1),
           let count = Int(arguments[index + 1]) {
            UserDefaults.standard.set(count, forKey: dismissCountKey)
        }
    }
}
