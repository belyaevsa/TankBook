import SwiftUI
import TankbookCore

/// RV.71 (2026-09-05, product owner): the amber "the scan's fuel kind doesn't
/// match this car" warning under the fuel card on the scanned Confirm sheet.
/// It renders only at the scan moment, when the extraction resolved a kind the
/// car's offer set does not include (`FuelKind.shouldWarnFuelMismatch` - the
/// comparison lives in core and tests at L1; this view only renders and
/// composes the message). It NEVER blocks the save and never rewrites either
/// value (hard rule 13): the extracted kind stays a default input the user
/// edits. Amber is attention, never colour alone (hard rule 5) - the words
/// carry the meaning for VoiceOver - and the copy names its next step (hard
/// rule 7). The × dismisses it for this sheet without touching the form.
///
/// The view owns its own dismissal state (`@State`) and keeps itself in the
/// hierarchy after a dismiss by rendering `EmptyView` rather than vanishing -
/// so a parent re-render cannot resurrect a dismissed warn (the currency
/// section's `@State` trap, ManualFillUpCurrencySupport). A NEW sheet builds a
/// new identity, so the next scan warns again when the disagreement is real.
struct FuelKindMismatchNotice: View {
    /// The scan's resolved kind; nil on the typed path and on a scan that read
    /// no kind.
    let scannedKind: FuelKind?
    /// The car's own declared kinds (docs/SCHEMA.md, Vehicle.fuelKinds).
    let fuelKinds: [FuelKind]

    @State private var dismissed = false

    /// The car's offer set does not include the scanned kind - the pure rule,
    /// including both carve-outs (empty `fuelKinds`, `electricity` either way).
    /// Only the SCAN's resolved kind is consulted, never the form's chips: a
    /// disagreeing kind is not applied as the form default (apply guards on
    /// `vehicle.fuelKinds.contains`), so the mismatch must be read from the
    /// extraction, not from the selection.
    private var showsMismatch: Bool {
        guard let scannedKind else { return false }
        return FuelKind.shouldWarnFuelMismatch(scannedKind: scannedKind,
                                               vehicleFuelKinds: Set(fuelKinds))
    }

    var body: some View {
        if showsMismatch, !dismissed, let scannedKind {
            row(scannedKind: scannedKind)
        } else {
            // Stay in the hierarchy (see the note above): a dismissed or
            // non-applicable warn occupies no space and cannot be resurrected
            // by a parent re-render.
            EmptyView()
        }
    }

    private func row(scannedKind: FuelKind) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
            Text(L10n.fuelKindMismatchMessage(scannedKind: scannedKind,
                                              declaredKinds: fuelKinds))
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("manualFillUpFuelMismatchMessage")
            Button {
                dismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("manualFillUpFuelMismatchDismiss")
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 10)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("manualFillUpFuelMismatchWarning")
    }
}
