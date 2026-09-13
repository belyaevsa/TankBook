import SwiftUI
import TankbookCore

/// The odometer card shared by the non-fill Edit entry screen and the Expense
/// capture screen: a labelled row, the field and the car's distance unit. One
/// view, several form states - the capture door must render the same card the
/// edit door does (docs/JOURNEYS.md J3b), so it is lifted rather than copied.
/// The service capture keeps its own two-column date/odometer card.
struct EntryOdometerCard<Focus: Hashable>: View {
    @Binding var odometer: String
    @FocusState.Binding var focus: Focus?
    let target: Focus
    let distanceUnit: DistanceUnit
    var rowIdentifier: String?
    var fieldIdentifier: String

    var body: some View {
        FocusableFieldRow("Odometer", $focus, equals: target,
                          rowIdentifier: rowIdentifier) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField("", text: $odometer)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.custom(AppFonts.dinAlternateBold, size: 24))
                    .foregroundStyle(Theme.Palette.ink)
                    .focused($focus, equals: target)
                    .accessibilityIdentifier(fieldIdentifier)
                    .numericInput($odometer, kind: .integer)
                    .onChange(of: focus) { oldValue, newValue in
                        if newValue == target {
                            odometer = OdometerFormat.ungrouped(odometer)
                        } else if oldValue == target, let value = odometerValue {
                            odometer = OdometerFormat.grouped(value)
                        }
                    }
                Text(L10n.distanceUnit(distanceUnit))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
        .formCard()
    }

    private var odometerValue: Int? {
        let trimmed = odometer.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Int(OdometerFormat.ungrouped(trimmed))
    }
}
