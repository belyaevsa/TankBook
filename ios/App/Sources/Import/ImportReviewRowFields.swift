import SwiftUI
import TankbookCore

// The review row's labelled field cells (design/screens/ImportReview.dc.html,
// docs/JOURNEYS.md F6b): parsed values with the one field that is wrong marked,
// and a missing value rendered as a blank "– km" - an honest absence, never `0`.

/// The PJ.11 timeline-conflict detail cell: the conflicting entry is quoted
/// when the order check has a neighbour to name ("Aug 17 already recorded
/// 119 486 km."), the generic pace wording otherwise. Amber - the row stays
/// committable (hard rule 13: the user decides, the flag is the warning).
struct ImportTimelineDetail: View {
    let row: ImportReviewRow

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
            timelineText
                .font(.caption)
                .foregroundStyle(Theme.Palette.warn)
                .lineSpacing(1.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .accessibilityIdentifier("importReviewTimelineDetail")
    }

    @ViewBuilder
    private var timelineText: some View {
        if let quote = timelineQuote {
            Text(quote)
        } else {
            Text("Odometer breaks the timeline – check it.")
        }
    }

    /// The F9a order quote when the partition's flag carried a previous
    /// neighbour ("Aug 17 already recorded 119 486 km." - the same wording the
    /// Confirm sheet uses). A pace-only flag has no neighbour to quote.
    private var timelineQuote: String? {
        guard case .timelineConflict = row.kind,
              let timeline = row.timeline,
              timeline.kind == .order,
              let previousOdometer = timeline.previousOdometer,
              let previousDate = timeline.previousDate,
              let fill = row.fill, let odo = fill.odometer, odo <= previousOdometer else {
            return nil
        }
        let day = previousDate.formatted(.dateTime.month(.abbreviated).day())
        return String(format: L10n.localize("%@ already recorded %@ km."),
                      day, OdometerFormat.grouped(previousOdometer))
    }
}

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
/// A PJ.11 timeline-conflict row marks the cell amber too (F6b: only the
/// broken field is marked - for a timeline violation the odometer is the field
/// that broke the order).
struct ImportOdometerCell: View {
    let fill: FillUp
    let sourceRow: Int
    let distanceUnit: DistanceUnit
    let isEditing: Bool
    @Binding var text: String
    var onSubmit: () -> Void
    var marked = false

    var body: some View {
        let missing = fill.odometer == nil
        let amber = missing || marked
        VStack(alignment: .leading, spacing: 2) {
            Text("Odometer")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(amber ? Theme.Palette.warn : Theme.Palette.inkSoft)
            if isEditing {
                TextField("Odometer", text: $text)
                    .keyboardType(.numberPad)
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.ink)
                    .submitLabel(.done)
                    .onSubmit(onSubmit)
                    .numericInput($text, kind: .integer)
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
                .stroke(amber ? Theme.Palette.warn.opacity(0.7) : Color.clear, lineWidth: 1)
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
                .numericInput($text, kind: .decimal)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.midnight)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
