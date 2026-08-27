import SwiftUI
import TankbookCore

// The review row's labelled field cells (design/screens/ImportReview.dc.html,
// docs/JOURNEYS.md F6b): parsed values with the one field that is wrong marked,
// and a missing value rendered as a blank "– km" - an honest absence, never `0`.

/// A generic labelled field cell ("Litres", "Price/L", "Total", "Note").
struct ImportFieldCell: View {
    let label: LocalizedStringKey
    let value: String
    var marked = false
    var valueColor: Color = Theme.Palette.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(marked ? Theme.Palette.warn : Theme.Palette.inkSoft)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.midnight)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(marked ? Theme.Palette.warn.opacity(0.7) : Color.clear, lineWidth: 1)
        )
    }
}

/// The odometer cell. A missing value renders as a blank "– km" with its own
/// amber underline - never `0` (F6b). "Add odometer" swaps in a number field.
struct ImportOdometerCell: View {
    let fill: FillUp
    let sourceRow: Int
    let distanceUnit: DistanceUnit
    let isEditing: Bool
    @Binding var text: String
    var onSubmit: () -> Void

    var body: some View {
        let missing = fill.odometer == nil
        VStack(alignment: .leading, spacing: 2) {
            Text("Odometer")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(missing ? Theme.Palette.warn : Theme.Palette.inkSoft)
            if isEditing {
                TextField("Odometer", text: $text)
                    .keyboardType(.numberPad)
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.ink)
                    .submitLabel(.done)
                    .onSubmit(onSubmit)
            } else if let odo = fill.odometer {
                Text("\(ImportFormatting.odometer(odo)) \(L10n.distanceUnit(distanceUnit))")
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.ink)
            } else {
                Text(verbatim: "– \(L10n.distanceUnit(distanceUnit))")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.Palette.inkSoft.opacity(0.6))
                    .accessibilityIdentifier("importReviewMissingOdometer-\(sourceRow)")
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.midnight)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(missing ? Theme.Palette.warn.opacity(0.7) : Color.clear, lineWidth: 1)
        )
    }
}

/// The total's inline editor ("Fix" on a cross-check-mismatch row).
struct ImportTotalEditorCell: View {
    @Binding var text: String
    var onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Total")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.inkSoft)
            TextField("Total", text: $text)
                .keyboardType(.decimalPad)
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.ink)
                .submitLabel(.done)
                .onSubmit(onSubmit)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.midnight)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
