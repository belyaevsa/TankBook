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

// MARK: - The purchase link

/// The `.parts` expense's door to its tire set (docs/JOURNEYS.md J7b "a tire
/// purchase becomes a TireSet"). Unlinked, it offers "Make this a tire set";
/// linked, it names the set and pushes its form, so the purchase is visible
/// from the expense that made it.
struct TireSetPurchaseCard: View {
    let linkedSet: TireSet?
    let onMake: () -> Void

    var body: some View {
        if let linkedSet {
            NavigationLink(value: Route.tireSetForm(linkedSet.id)) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .frame(width: 19, height: 19)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This purchase is a tire set")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.inkSoft)
                        Text(linkedSet.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.ink)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .padding(14)
                .formCard()
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tireSetPurchaseLink")
        } else {
            Button(action: onMake) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                    Text("Make this a tire set")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Theme.Palette.action)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .strokeBorder(Theme.Palette.hairline,
                                      style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("makeTireSetButton")
        }
    }
}

/// The set form's purchase card: which expense bought this set, with its amount
/// and date. The link is stored by id, so it survives any edit of the expense's
/// words - this reads the expense back rather than deriving it from the name.
struct TireSetPurchaseInfoCard: View {
    let expense: Expense

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "cart")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(width: 19, height: 19)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bought with")
                    .font(.caption)
                    .textCase(.uppercase)
                    .tracking(1.0)
                    .foregroundStyle(Theme.Palette.inkSoft)
                Text(expense.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(2)
                Text(amountAndDate)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .formCard()
        .accessibilityIdentifier("tireSetPurchaseExpense")
    }

    private var amountAndDate: String {
        let date = ReminderRowFormat.dateString(expense.date)
        guard let money = expense.money else { return date }
        let amount = HomeFormat.entryAmount(
            money.amount, symbol: AddVehicleSupport.moneySymbol(for: money.currency))
        return "\(amount) · \(date)"
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
