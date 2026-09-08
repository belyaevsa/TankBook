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
/// "Check for rates" action that runs the demand drain over the pending rows'
/// own dates - the pass RV.111 gave it.
///
/// RV.111: when `deadEnd` is true the same count must NOT promise another
/// check. A demand pass that reached the provider and still left these dates
/// pending has exhausted what any future pass can serve (their dates predate
/// the rolling pack window), so the next step is the manual rate on each
/// entry (hard rule 13) - shown as a second caption line, never a button.
///
/// RV.132: the check is a user-initiated drain and the tap is acknowledged
/// IMMEDIATELY - the action swaps to an inline "Checking for rates…" line the
/// moment it is tapped, before the network resolves, so a slow provider never
/// reads as a dead button (the reported symptom). The resolved outcome then
/// lands on the app toast (filled / nothing pending) while this footnote's
/// standing changes - the count draining, the dead-end copy flipping - happen
/// on the drain's own silent reload (docs/ERRORS.md -> Home).
struct PendingRatesFootnote: View {
    let count: Int
    let identifier: String
    /// The demand drain the check runs; `nil` renders the passive caption alone.
    /// Async so the footnote can hold the busy acknowledgement until it returns.
    var onCheck: (() async -> Void)?
    /// RV.111: render the dead-end next step (manual rate) instead of the
    /// check action - see `showsDeadEnd`.
    var deadEnd: Bool = false

    /// RV.132: whether a demand drain is on the wire. Set synchronously in the
    /// action, cleared when the drain returns - this is the immediate
    /// acknowledgement that a tap did something.
    @State private var isChecking = false

    var body: some View {
        if deadEnd {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.pendingRates(count))
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier(identifier)
                Text(L10n.pendingRatesDeadEnd)
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier(identifier + "ManualRate")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(L10n.pendingRates(count))
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier(identifier)
                Spacer(minLength: 0)
                if isChecking {
                    checkingRow
                } else if let onCheck {
                    Button(action: { beginCheck(onCheck) }) {
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

    /// The immediate acknowledgement (RV.132): a compact busy line where the
    /// action sat. It renders the instant the button is tapped - never only
    /// once the response lands - and disappears when the drain returns. The
    /// text carries the identifier (like the count line above), so a test can
    /// assert the acknowledgement by name.
    private var checkingRow: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
            Text(L10n.checkingForRates)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .accessibilityIdentifier(identifier + "Checking")
        }
    }

    /// RV.132: set the busy state synchronously, then await the drain. The
    /// footnote re-offers the check when the drain leaves rows pending; a fill
    /// or dead end redraws it through the drain's own silent reload.
    private func beginCheck(_ onCheck: @escaping () async -> Void) {
        isChecking = true
        Task {
            await onCheck()
            isChecking = false
        }
    }
}

extension PendingRatesFootnote {
    /// RV.111: whether this scope's footnote shows the dead-end next step. The
    /// last demand pass must have REACHED the provider and left an
    /// unresolvable row (one dated before the rolling pack window - no future
    /// launch refresh re-asks it and a re-ask of the same dates is answered
    /// empty), and the scope must still hold such a row: a row that entered
    /// the log afterwards (and was never demanded) keeps the check affordance.
    @MainActor
    static func showsDeadEnd(_ entries: [any Entry]) -> Bool {
        guard AppRates.demandPassLeftUnresolvableRows else { return false }
        let calendar = Calendar.current
        let windowFrom = RateStore.rollingPackFrom(now: Date(), calendar: calendar)
        return entries.contains { entry in
            guard entry.money?.isRatePending == true else { return false }
            return calendar.startOfDay(for: entry.date) < windowFrom
        }
    }
}
