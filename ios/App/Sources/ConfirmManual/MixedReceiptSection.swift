import SwiftUI
import TankbookCore

// MARK: - "Also on this receipt" (P2.4)
//
// The Confirm sheet's mixed-receipt section (design/screens/ConfirmMixed.dc.html):
// the fuel line stays the fill-up, and the non-fuel lines the detector found are
// offered as separate Expenses the user accepts or dismisses individually. Each
// row is a default input, never a fact (hard rule 13) - the toggle flips it,
// nothing is created until Save, and the footer shows the receipt total against
// what the group actually logs.

struct MixedReceiptSection: View {
    let lines: [ReceiptLineItem]
    @Binding var acceptedLineIDs: Set<UUID>
    let currencySymbol: String
    let receiptTotal: Decimal
    let fillUpAmount: Decimal

    private var loggedTotal: Decimal {
        fillUpAmount + lines
            .filter { acceptedLineIDs.contains($0.id) }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow("Also on this receipt")
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                lineRow(line, index: index)
            }
            footer
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mixedReceiptSection")
    }

    private func lineRow(_ line: ReceiptLineItem, index: Int) -> some View {
        let accepted = acceptedLineIDs.contains(line.id)
        return HStack(spacing: 11) {
            Circle()
                .fill(accepted ? Theme.Palette.inkSoft : Theme.Palette.hairline)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(line.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                Text(subtitle(for: line, accepted: accepted))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(money(line.amount))
                .font(.custom(AppFonts.dinAlternateBold, size: 15))
                .foregroundStyle(accepted ? Theme.Palette.ink : Theme.Palette.inkSoft)
                .accessibilityIdentifier("mixedReceiptAmount_\(index)")
            Toggle("", isOn: binding(for: line))
                .labelsHidden()
                .tint(Theme.Palette.taillight)
                .accessibilityIdentifier("mixedReceiptToggle_\(index)")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
    }

    private func subtitle(for line: ReceiptLineItem, accepted: Bool) -> String {
        if accepted {
            return String(format: L10n.localize("Adds as expense · %@"),
                          L10n.expenseCategoryLabel(line.category))
        }
        if line.isCarRelated {
            return L10n.localize("Not logged")
        }
        return L10n.localize("Not car-related · skipped")
    }

    private func binding(for line: ReceiptLineItem) -> Binding<Bool> {
        Binding(
            get: { acceptedLineIDs.contains(line.id) },
            set: { accepted in
                if accepted {
                    acceptedLineIDs.insert(line.id)
                } else {
                    acceptedLineIDs.remove(line.id)
                }
            }
        )
    }

    private var footer: some View {
        HStack {
            Spacer(minLength: 0)
            Text(String(format: L10n.localize("Receipt total %1$@ · logging %2$@"),
                        money(receiptTotal), money(loggedTotal)))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .accessibilityIdentifier("mixedReceiptFooter")
        }
        .padding(.top, 2)
    }

    private func money(_ amount: Decimal) -> String {
        "\(ManualFillUpFormat.decimal(amount, fractionDigits: 2)) \(currencySymbol)"
    }
}
