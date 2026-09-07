import SwiftUI
import TankbookCore

/// The "N entries pending rates" footnote shared by Home and Trends
/// (docs/JOURNEYS.md F9: "entry shows original currency in trends with a
/// footnote count"; the count is `pendingRateCount`, derived by P5.2a - this
/// component only renders it).
///
/// It is NOT an error and NOT amber-as-alarm (docs/ERRORS.md severity
/// vocabulary): nothing is wrong, the entry's home amount is simply not known
/// yet - so it renders as a passive `inkSoft` hint, never `warn`. It
/// disappears at zero (callers render it only when the count is > 0), and a
/// backfill that fills the entry removes it silently - no toast, nothing was
/// wrong (docs/SYNC.md S8). Same shape as `ExcludedEntriesFootnote`, without
/// the link (F9 names no tap-through; the manual rate lives on the entry's own
/// edit screen).
///
/// RV.106: the footnote names its next step (hard rule 7). A count with no
/// affordance gave the user no way to ask for a re-check and no idea whether
/// waiting would help, so when `onCheck` is supplied the row carries a
/// "Check for rates" action that re-runs the rate refresh + S8 backfill - the
/// same pass the next launch would run, on demand.
struct PendingRatesFootnote: View {
    let count: Int
    let identifier: String
    /// The "check for rates" action; `nil` renders the passive caption alone.
    var onCheck: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(L10n.pendingRates(count))
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft)
                .accessibilityIdentifier(identifier)
            Spacer(minLength: 0)
            if let onCheck {
                Button(action: onCheck) {
                    Text(L10n.checkForRates)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Palette.action)
                }
                .buttonStyle(.plain)
                .accessibilityHint(L10n.checkForRatesHint)
                .accessibilityIdentifier(identifier + "CheckButton")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
