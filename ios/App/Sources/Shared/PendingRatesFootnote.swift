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
struct PendingRatesFootnote: View {
    let count: Int
    let identifier: String

    var body: some View {
        Text(L10n.pendingRates(count))
            .font(.caption2)
            .foregroundStyle(Theme.Palette.inkSoft)
            .accessibilityIdentifier(identifier)
    }
}
