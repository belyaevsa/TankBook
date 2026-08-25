import SwiftUI
import TankbookCore

// MARK: - The row

/// One tire-set row: the name and its derived mileage ("Winter Nokian" /
/// "18 400 km", or "–" when unknowable). Tapping the row renames the set; the
/// trailing menu archives it (a tombstone - docs/SCHEMA.md soft-delete, 30-day
/// undo, hard rule 8).
struct TireSetRow: View {
    let tireSet: TireSet
    let mileage: Int?
    let distanceUnit: DistanceUnit
    let onArchive: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(width: 19, height: 19)
            VStack(alignment: .leading, spacing: 2) {
                Text(tireSet.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(2)
                Text(TireSetRowFormat.mileageText(km: mileage, distanceUnit: distanceUnit))
                    .font(.custom(AppFonts.dinAlternateBold, size: 15))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("tireSetMileage")
            }
            Spacer(minLength: 0)
            Menu {
                Button(action: onArchive) {
                    Label("Archive", systemImage: "archivebox")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("Tire set actions")
            .accessibilityIdentifier("tireSetRowMenu")
        }
        .padding(14)
        .formCard()
        .accessibilityElement(children: .contain)
    }
}

// MARK: - The name field

/// The one field a tire set has: its name. The same card metrics, eyebrow and
/// underline as the ServiceEntry and Reminder forms (no artboard exists for
/// tire sets, so it follows those).
struct TireSetNameCard: View {
    @Binding var name: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Name")
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(1.0)
                .foregroundStyle(Theme.Palette.inkSoft)
            TextField("Tire set name", text: $name)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.ink)
                .focused(focused)
                .fieldUnderline(isFocused: focused.wrappedValue, warn: false)
                .accessibilityIdentifier("tireSetNameField")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .formCard()
    }
}
